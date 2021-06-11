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
  apply_win_signs: function(bufnr: integer, pending: {integer:Sign}, top: integer, bot: integer)
  on_lines: function(buf: integer, last_orig: integer, last_new: integer): boolean

  apply_word_diff: function(buf: integer, row: integer)

  setup: function()
end

function M.apply_win_signs(bufnr: integer, pending: {integer:Sign}, top: integer, bot: integer)
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

  if first_apply then
    signs.remove(bufnr)  -- Remove all signs

    -- To stop the sign column width changing too much, if there are signs to be
    -- added but none of them are visible in the window, then make sure to add at
    -- least one sign. Only do this on the first call after an update when we all
    -- the signs have been cleared.
    if config.use_decoration_api then
      schedule_sign(next(pending))
    end
  end

  signs.add(config, bufnr, scheduled)

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

      -- Add 'added' signs only if there wasn't a 'delete' sign above
      if not placed or not vim.startswith(placed, 'GitSignsTopDelete') then
        -- If lines are added, make sure to immediately add the signs
        for i = 1, last_new do
          signs.add(config, buf, {[i] = {type='add', count=0}})
        end
      else
        signs.remove(buf, 1)
      end
    else
      local placed = signs.get(buf, last_orig)[last_orig]

      -- Add 'added' signs only if there wasn't a 'delete' sign above
      if not placed or not vim.startswith(placed, 'GitSignsDelete') then
        -- If lines are added, make sure to immediately add the signs
        for i = last_orig+1, last_new do
          signs.add(config, buf, {[i] = {type='add', count=0}})
        end
      end
    end
  else
    -- Line change

    local placed = signs.get(buf, last_orig)[last_orig]

    -- add a 'change' sign if there are no other signs
    if not placed then
      signs.add(config, buf, {[last_orig] = {type='change', count=0}})
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
  local cols = #api.nvim_buf_get_lines(bufnr, lnum-1, lnum, false)[1]

  for _, hunk in ipairs(cache[bufnr].hunks) do
    if lnum >= hunk.start and lnum <= hunk.vend then
      local size = #hunk.lines / 2
      local regions = require('gitsigns.diff').run_word_diff(hunk.lines)
      for _, region in ipairs(regions) do
        local line = region[1]
        if lnum == hunk.start + line - size - 1
          and vim.startswith(hunk.lines[line], '+') then
          local rtype = region[2]
          local scol = region[3] - 1
          local ecol = region[4] - 1
          if ecol > cols then
            ecol = cols
          end
          api.nvim_buf_set_extmark(bufnr, ns, row, scol, {
            end_col = ecol,
            hl_group = rtype == 'add'    and 'GitSignsAddLn'
                    or rtype == 'change' and 'GitSignsChangeLn' or
                                             'GitSignsDeleteLn',
            ephemeral = true
          })
        end
      end
      break
    end
  end
end

local update_cnt = 0

local update0 = async(function(bufnr: integer, bcache: CacheEntry)
  bcache = bcache or cache[bufnr]
  if not bcache then
    error('Cache for buffer '..bufnr..' was nil')
    return
  end
  bcache.hunks = nil

  await(scheduler())
  local buftext = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local git_obj = bcache.git_obj

  local compare_object = bcache.get_compare_obj(bcache)

  if config.use_internal_diff then
    local diff = require('gitsigns.diff')
    if not bcache.compare_text or config._refresh_staged_on_update then
      bcache.compare_text = await(git_obj:get_show_text(compare_object))
    end
    bcache.hunks = diff.run_diff(bcache.compare_text, buftext, config.diff_algorithm)
  else
    await(git_obj:get_show(compare_object, bcache.compare_file))
    bcache.hunks = await(git.run_diff(bcache.compare_file, buftext, config.diff_algorithm))
  end
  bcache.pending_signs = gs_hunks.process_hunks(bcache.hunks)

  await(scheduler())

  -- Apply signs to the window. Other signs will be added by the decoration
  -- provider as they are drawn.
  M.apply_win_signs(bufnr, bcache.pending_signs)

  Status:update(bufnr, gs_hunks.get_summary(bcache.hunks, git_obj.abbrev_head))

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
