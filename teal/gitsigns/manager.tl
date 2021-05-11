local a = require('plenary.async_lib.async')
local await      = a.await
local async      = a.async
local void       = a.void
local scheduler  = a.scheduler

local sleep = require('plenary.async_lib.util').sleep

local gs_cache = require('gitsigns.cache')
local CacheEntry = gs_cache.CacheEntry
local cache = gs_cache.cache

local signs             = require('gitsigns.signs')
local Sign              = signs.Sign

local Status            = require("gitsigns.status")

local debounce_trailing = require('gitsigns.debounce').debounce_trailing
local gs_debug          = require("gitsigns.debug")
local dprint            = gs_debug.dprint
local util              = require('gitsigns.util')
local git               = require('gitsigns.git')
local gs_hunks          = require("gitsigns.hunks")

local config         = require('gitsigns.config').config

local api = vim.api

local record M
  update: a.async_fun1<integer>
  update_debounced: function(integer, CacheEntry)
  apply_win_signs: function(bufnr: integer, top: integer, bot: integer)
  on_lines: function(buf: integer, last_orig: integer, last_new: integer): boolean

  apply_word_diff: function(buf: integer, row: integer)

  setup: function()
end

local function apply_win_signs0(bufnr: integer, pending: {integer:Sign}, top: integer, bot: integer, sec: boolean)
  if not pending then return end

  -- If called without top or bot, then assume this is the first call after
  -- clearing all the signs
  local first_apply = top == nil

  if config.use_decoration_api then
    -- Just apply to signs visible in window
    top = top or vim.fn.line('w0')
    bot = bot or vim.fn.line('w$')
  else
    top = top or 1
    bot = bot or vim.fn.line('$')
  end

  local scheduled: {integer:Sign} = {}

  local function schedule_sign(n: integer, _: any)
    if n and pending[n] then
      scheduled[n] = pending[n]
      pending[n] = nil
    end
  end

  for lnum = top, bot do
    schedule_sign(lnum)
  end

  -- To stop the sign column width changing too much, if there are signs to be
  -- added but none of them are visible in the window, then make sure to add at
  -- least one sign. Only do this on the first call after an update when we all
  -- the signs have been cleared.
  if first_apply and config.use_decoration_api then
    schedule_sign(next(pending))
  end

  signs.add(config, bufnr, scheduled, sec)
end

function M.apply_win_signs(bufnr: integer, top: integer, bot: integer)
  local bcache = cache[bufnr]
  if not bcache then return end

  -- If called without top or bot, then assume this is the first call after
  -- clearing all the signs
  local first_apply = top == nil

  if first_apply then
    signs.remove(bufnr, nil, true)  -- Remove all signs
    signs.remove(bufnr, nil, false)  -- Remove all signs
  end

  apply_win_signs0(bufnr, bcache.sec.pending_signs , top, bot, true )
  apply_win_signs0(bufnr, bcache.main.pending_signs, top, bot, false)
end

-- Speculate on future signs. It's not a big deal if we speculate incorrectly as
-- update() will overwrite all the signs anyway. This has noticeable effect on
-- large files and even makes small files feel very snappy.
local function speculate_signs(buf: integer, last_orig: integer, last_new: integer)
  if last_new < last_orig then
    -- Lines removed
    --
    -- Cannot do much here due to https://github.com/neovim/neovim/pull/12323
  elseif last_new > last_orig then
    -- Lines added

    if last_orig == 0 then
      -- Note: It seems that
      local placed = signs.get(buf, 1)[1]
      local place_empty = signs.has_empty(buf)

      -- Add 'added' signs only if there wasn't a 'delete' sign above
      if not placed or not vim.startswith(placed, 'GitSignsTopDelete') then
        -- If lines are added, make sure to immediately add the signs
        for i = 1, last_new do
          signs.add_one(config, buf, i, 'add')
          if place_empty then
            signs.add_empty_sec(config, buf, i)
          end
        end
      else
        signs.remove(buf, 1)
      end
    else
      local placed = signs.get(buf, last_orig)[last_orig]
      local place_empty = signs.has_empty(buf)

      -- Add 'added' signs only if there wasn't a 'delete' sign above
      if not placed or not vim.startswith(placed, 'GitSignsDelete') then
        -- If lines are added, make sure to immediately add the signs
        for i = last_orig+1, last_new do
          signs.add_one(config, buf, i, 'add')
          if place_empty then
            signs.add_empty_sec(config, buf, i)
          end
        end
      end
    end
  else
    -- Line change

    local placed = signs.get(buf, last_orig)[last_orig]

    -- add a 'change' sign if there are no other signs
    if not placed then
      signs.add_one(config, buf, last_orig, 'change')
      if signs.has_empty(buf) then
        signs.add_empty_sec(config, buf, last_orig)
      end
    end
  end
end

M.on_lines = function(buf: integer, last_orig: integer, last_new: integer): boolean
  if not cache[buf] then
    dprint('Cache for buffer '..buf..' was nil. Detaching')
    return true
  end

  speculate_signs(buf, last_orig, last_new)
  M.update_debounced(buf)
end

local ns = api.nvim_create_namespace('gitsigns')

M.apply_word_diff = function(bufnr: integer, row: integer)
  if not cache[bufnr] then return end

  local lnum = row + 1

  for _, hunk in ipairs(cache[bufnr].main.hunks) do
    if lnum >= hunk.start and lnum <= hunk.vend then
      local regions = require('gitsigns.word_diff').process(hunk.lines)
      for _, region in ipairs(regions) do
        if region[2] == '+' then
          local line = region[1]
          if hunk.start + (line /2) - 1 == lnum then
            local scol = region[3]-1
            local ecol = region[4]-1
            api.nvim_buf_set_extmark(bufnr, ns, row, scol-1, {
              end_col = ecol,
              hl_group = 'GitSignsAddLn',
              ephemeral = true
            })
          end
        end
      end
      break
    end
  end
end

local function staged_signs_enabled(c: CacheEntry): boolean
  return config.staged_signs and c.main.base == nil or c.sec.base ~= nil
end

local update_cnt = 0

local update0 = async(function(bufnr: integer, bcache: CacheEntry)
  bcache = bcache or cache[bufnr]
  if not bcache then
    error('Cache for buffer '..bufnr..' was nil')
    return
  end

  await(scheduler())
  local buftext = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local git_obj = bcache.git_obj

  local show_sec = staged_signs_enabled(bcache)

  for i, o in ipairs{bcache.main, bcache.sec} do
    local sec = i==2

    if sec and not show_sec then
      break
    end

    local compare_object = bcache:get_compare_obj(o.base, sec)

    if config.use_internal_diff then
      local diff = require('gitsigns.diff')
      if not o.compare_text or config._refresh_staged_on_update then
        o.compare_text = await(git_obj:get_show_text(compare_object))
      end
      o.hunks = diff.run_diff(o.compare_text, buftext, config.diff_algorithm)
    else
      await(git_obj:get_show(compare_object, o.compare_file))
      o.hunks = await(git.run_diff(o.compare_file, buftext, config.diff_algorithm))
    end

    o.pending_signs = gs_hunks.process_hunks(o.hunks)
  end

  -- secondary signs is staged hunks. Simply remove the index signs from the
  -- HEAD signs.
  if config.staged_signs and bcache.main.base == nil and bcache.sec.base == nil then
    local fill_empty = false
    for i, ms in pairs(bcache.main.pending_signs or {}) do
      local ps = bcache.sec.pending_signs[i]
      if ps then
        if ps.type == ms.type then
          bcache.sec.pending_signs[i] = nil
        else
          fill_empty = true
        end
      end
    end

    -- If there are any main and sec signs on the same line then insert empty
    -- sec signs on every main sign line to ensure all main signs are aligned.
    if fill_empty then
      for i, _ in pairs(bcache.main.pending_signs or {}) do
        local ps = bcache.sec.pending_signs[i]
        if not ps then
          bcache.sec.pending_signs[i] = {type='empty', count=0}
        end
      end
    end
  end

  await(scheduler())

  -- Apply signs to the window. Other signs will be added by the decoration
  -- provider as they are drawn.
  M.apply_win_signs(bufnr)

  Status:update(bufnr, gs_hunks.get_summary(bcache.main.hunks, git_obj.abbrev_head))

  update_cnt = update_cnt + 1

  local update_str = string.format('updates: %s, jobs: %s', update_cnt, util.job_cnt)
  dprint(update_str, bufnr, 'update')
  if config.debug_mode then
    api.nvim_set_var('gs_dev', update_str)
  end
end)

-- Ensure updates cannot be interleaved.
-- Since updates are asynchronous we need to make sure an update isn't performed
-- whilst another one is in progress. If this happens then schedule another
-- update after the current one has completed.
do
  local running = false
  local scheduled: {integer:boolean} = {}
  M.update = async(function(bufnr: integer)
    scheduled[bufnr] = true
    if not running then
      running = true
      while scheduled[bufnr] do
        scheduled[bufnr] = false
        await(update0(bufnr))
      end
      running = false
    else
      -- Wait until all updates have finished
      while running do
        await(sleep(100))
      end
    end
  end)
end

M.setup = function()
  M.update_debounced = debounce_trailing(config.update_debounce, void(M.update)) as function(integer)
end

return M
