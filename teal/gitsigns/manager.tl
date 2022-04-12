local void = require('gitsigns.async').void
local awrap = require('gitsigns.async').wrap

local gs_cache = require('gitsigns.cache')
local CacheEntry = gs_cache.CacheEntry
local cache = gs_cache.cache

local signs             = require('gitsigns.signs')

local Status            = require("gitsigns.status")

local debounce_trailing = require('gitsigns.debounce').debounce_trailing
local throttle_by_id    = require('gitsigns.debounce').throttle_by_id
local gs_debug          = require("gitsigns.debug")
local dprint            = gs_debug.dprint
local dprintf           = gs_debug.dprintf
local eprint            = gs_debug.eprint
local subprocess        = require('gitsigns.subprocess')
local util              = require('gitsigns.util')
local run_diff          = require('gitsigns.diff')

local gs_hunks          = require("gitsigns.hunks")
local Hunk              = gs_hunks.Hunk

local config            = require('gitsigns.config').config

local api = vim.api

local record M
  update           : function(integer, CacheEntry)
  update_debounced : function(integer, CacheEntry)
  apply_win_signs  : function(bufnr: integer, {Hunk}, top: integer, bot: integer)
  on_lines         : function(buf: integer, last_orig: integer, last_new: integer): boolean

  apply_word_diff: function(buf: integer, row: integer)

  setup: function()
end

local schedule_if_buf_valid = function(buf: integer, cb: function)
  vim.schedule(function()
    if vim.api.nvim_buf_is_valid(buf) then
      cb()
    end
  end)
end

local scheduler_if_buf_valid = awrap(schedule_if_buf_valid, 2)

function M.apply_win_signs(bufnr: integer, hunks: {Hunk}, top: integer, bot: integer, clear: boolean)
  if clear then
    signs.remove(bufnr)  -- Remove all signs
  end

  -- To stop the sign column width changing too much, if there are signs to be
  -- added but none of them are visible in the window, then make sure to add at
  -- least one sign. Only do this on the first call after an update when we all
  -- the signs have been cleared.

  for i, hunk in ipairs(hunks or {}) do
    if clear and i == 1
        or top <= hunk.vend and bot >= hunk.start then
      signs.schedule(config, bufnr, gs_hunks.calc_signs(hunk))
    end
    if hunk.start > bot then
      break
    end
  end

  signs.draw(bufnr, top, bot)
end

M.on_lines = function(buf: integer, _: integer, _: integer): boolean
  local bcache = cache[buf]
  if not bcache then
    dprint('Cache for buffer was nil. Detaching')
    return true
  end

  M.update_debounced(buf, cache[buf])
end

local ns = api.nvim_create_namespace('gitsigns')

M.apply_word_diff = function(bufnr: integer, row: integer)
  if not cache[bufnr] or not cache[bufnr].hunks then
    return
  end

  local line = api.nvim_buf_get_lines(bufnr, row, row+1, false)[1]
  if not line then
    -- Invalid line
    return
  end

  local lnum = row + 1

  local hunk = gs_hunks.find_hunk(lnum, cache[bufnr].hunks)
  if not hunk then
    -- No hunk at line
    return
  end

  if hunk.added.count ~= hunk.removed.count then
    -- Only word diff if added count == removed
    return
  end

  local pos = lnum - hunk.start + 1

  local added_line = hunk.added.lines[pos]
  local removed_line = hunk.removed.lines[pos]

  local _, added_regions = require('gitsigns.diff_int').run_word_diff({removed_line}, {added_line})

  local cols = #line

  for _, region in ipairs(added_regions) do
    local rtype, scol, ecol = region[2], region[3], region[4]
    if scol <= cols then
      if ecol > cols then
        ecol = cols
      elseif ecol == scol then
        -- Make sure region is at least 1 column width
        ecol = scol + 1
      end
      api.nvim_buf_set_extmark(bufnr, ns, row, scol-1, {
        end_col = ecol-1,
        hl_group = rtype == 'add'    and 'GitSignsAddLnInline'
                or rtype == 'change' and 'GitSignsChangeLnInline'
                or                       'GitSignsDeleteLnInline',
        ephemeral = true,
        priority = 1000
      })
      api.nvim__buf_redraw_range(bufnr, row, row+1)
    end
  end
end

local ns_rm = api.nvim_create_namespace('gitsigns_removed')

local VIRT_LINE_LEN = 300

local function clear_deleted(bufnr: integer)
  local marks = api.nvim_buf_get_extmarks(bufnr, ns_rm, 0, -1, {})
  for _, mark in ipairs(marks as {{integer, integer, integer}}) do
    api.nvim_buf_del_extmark(bufnr, ns_rm, mark[1])
  end
end

local function show_deleted(bufnr: integer)
  local bcache = cache[bufnr]

   clear_deleted(bufnr)

   if not config.show_deleted then
     return
   end

  for _, hunk in ipairs(bcache.hunks) do
    local virt_lines = {}
    local do_word_diff = config.word_diff and #hunk.removed.lines == #hunk.added.lines

    for i, line in ipairs(hunk.removed.lines) do
      local vline = {}
      local last_ecol = 1

      if do_word_diff then
        local regions = require('gitsigns.diff_int').run_word_diff(
          {hunk.removed.lines[i]}, {hunk.added.lines[i]})

        for _, region in ipairs(regions) do
          local rline, scol, ecol = region[1], region[3], region[4]
          if rline > 1 then
            break
          end
          vline[#vline+1] = { line:sub(last_ecol, scol-1), 'GitsignsDeleteVirtLn'}
          vline[#vline+1] = { line:sub(scol, ecol-1), 'GitsignsDeleteVirtLnInline'}
          last_ecol = ecol
        end
      end

      if #line > 0 then
        vline[#vline+1] = { line:sub(last_ecol, -1), 'GitsignsDeleteVirtLn'}
      end

      -- Add extra padding so the entire line is highlighted
      local padding = string.rep(' ', VIRT_LINE_LEN-#line)
      vline[#vline+1] = { padding, 'GitsignsDeleteVirtLn'}

      virt_lines[i] = vline
    end

    api.nvim_buf_set_extmark(bufnr, ns_rm, hunk.start-1, -1, {
      virt_lines       = virt_lines,
      virt_lines_above = hunk.type ~= 'delete',
    })
  end
end

local update_cnt = 0

local update0 = function(bufnr: integer, bcache: CacheEntry)
  local __FUNC__ = 'update'
  bcache = bcache or cache[bufnr]
  if not bcache then
    eprint('Cache for buffer '..bufnr..' was nil')
    return
  end
  local old_hunks = bcache.hunks
  bcache.hunks = nil

  scheduler_if_buf_valid(bufnr)
  local buftext = util.buf_lines(bufnr)
  local git_obj = bcache.git_obj

  if not bcache.compare_text or config._refresh_staged_on_update then
    bcache.compare_text = git_obj:get_show_text(bcache:get_compare_rev())
  end

  bcache.hunks = run_diff(bcache.compare_text, buftext)

  scheduler_if_buf_valid(bufnr)
  if gs_hunks.compare_heads(bcache.hunks, old_hunks) then
    -- Apply signs to the window. Other signs will be added by the decoration
    -- provider as they are drawn.
    M.apply_win_signs(bufnr, bcache.hunks, vim.fn.line('w0'), vim.fn.line('w$'), true)

    show_deleted(bufnr)
  end
  local summary = gs_hunks.get_summary(bcache.hunks)
  summary.head = git_obj.repo.abbrev_head
  Status:update(bufnr, summary)

  update_cnt = update_cnt + 1

  dprintf('updates: %s, jobs: %s', update_cnt, subprocess.job_cnt)
end


-- Ensure updates cannot be interleaved.
-- Since updates are asynchronous we need to make sure an update isn't performed
-- whilst another one is in progress. If this happens then schedule another
-- update after the current one has completed.
M.update = throttle_by_id(update0, true) as function(integer, CacheEntry)

M.setup = function()
  M.update_debounced = debounce_trailing(config.update_debounce, void(M.update)) as function(integer)
end

return M
