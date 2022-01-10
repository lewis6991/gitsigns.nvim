local void = require('plenary.async.async').void
local awrap = require('plenary.async.async').wrap

local gs_cache = require('gitsigns.cache')
local CacheEntry = gs_cache.CacheEntry
local cache = gs_cache.cache

local signs             = require('gitsigns.signs')
local Sign              = signs.Sign

local Status            = require("gitsigns.status")

local debounce_trailing = require('gitsigns.debounce').debounce_trailing
local throttle_by_id    = require('gitsigns.debounce').throttle_by_id
local gs_debug          = require("gitsigns.debug")
local dprint            = gs_debug.dprint
local dprintf           = gs_debug.dprintf
local eprint            = gs_debug.eprint
local subprocess        = require('gitsigns.subprocess')
local util              = require('gitsigns.util')

local gs_hunks          = require("gitsigns.hunks")
local Hunk              = gs_hunks.Hunk
local HunkMark          = gs_hunks.HunkMark

local setup_highlights  = require('gitsigns.highlight').setup_highlights
local config            = require('gitsigns.config').config

local api = vim.api

local record M
  update           : function(integer, CacheEntry)
  update_debounced : function(integer, CacheEntry)
  apply_win_signs  : function(bufnr: integer, top: integer, bot: integer)
  apply_hunkmarks  : function(bufnr: integer, old_hmarks: {HunkMark}, new_hmarks: {HunkMark})
  clear_hunkmarks  : function(bufnr: integer)
  on_lines         : function(buf: integer, first: integer, integer, last_new: integer): boolean

  apply_word_diff: function(buf: integer, row: integer)

  setup: function()
  setup_signs_and_highlights: function(redefine: boolean)
end

local schedule_if_buf_valid = function(buf: integer, cb: function)
  vim.schedule(function()
    if vim.api.nvim_buf_is_valid(buf) then
      cb()
    end
  end)
end

local scheduler_if_buf_valid = awrap(schedule_if_buf_valid, 2)

function M.apply_win_signs(bufnr: integer, top: integer, bot: integer)
  local pending = cache[bufnr].pending_signs

  -- If called without top or bot, then assume this is the first call after
  -- clearing all the signs
  local first_apply = top == nil

  -- Just apply to signs visible in window
  top = top or vim.fn.line('w0')
  bot = bot or vim.fn.line('w$')

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
    schedule_sign(next(pending))
  end

  signs.add(config, bufnr, scheduled)

end

local ns_em = api.nvim_create_namespace('gitsigns_extmarks')

function M.apply_hunkmarks(bufnr: integer, old_hmarks: {HunkMark}, new_hmarks: {HunkMark})
  -- Remove existing
  if old_hmarks and old_hmarks[1] then
    for _, hm in ipairs(old_hmarks) do
      for _, id in ipairs(hm.ids) do
        assert(api.nvim_buf_del_extmark(bufnr, ns_em, id))
      end
      hm.ids = {}
    end
  else
    api.nvim_buf_clear_namespace(bufnr, ns_em, 0, -1)
  end

  for _, m in ipairs(new_hmarks or {}) do
    local scfg = config.signs[m.type]
    m.ids = m.ids or {}

    for i = m.start_line, m.end_line do
      local sign_text = config.signcolumn and scfg.text

      if i == m.start_line and config.signcolumn and scfg.show_count and m.count then
        local cc = config.count_chars
        local count_char = cc[m.count] or cc['+'] or ''
        sign_text = scfg.text..count_char
      end

      m.ids[#m.ids+1] = api.nvim_buf_set_extmark(bufnr, ns_em, i-1, -1, {
        id              = i,
        sign_text       = sign_text,
        sign_hl_group   = scfg.hl,
        number_hl_group = config.numhl and scfg.numhl or nil,
        line_hl_group   = config.linehl and scfg.linehl or nil,
      })
    end
  end
end

function M.clear_hunkmarks(bufnr: integer)
  M.apply_hunkmarks(bufnr)
end

M.on_lines = function(buf: integer, first: integer, last: integer, last_new: integer): boolean
  local bcache = cache[buf]
  if not bcache then
    dprint('Cache for buffer was nil. Detaching')
    return true
  end

  -- When there's a change that removes lines, remove extmarks in the range to
  -- prevent the extmarks from appearing on the line above.
  -- Note:
  --  - that this only happens when show_count=2.
  --  - that signs don't do this.
  if last_new == first then
    for _, hm in ipairs(bcache.hunk_marks) do
      if hm.ids and first+1 <= hm.end_line and last+1 >= hm.start_line then
        for _, id in ipairs(hm.ids) do
          assert(api.nvim_buf_del_extmark(buf, ns_em, id))
        end
        hm.ids = {}
      end
    end
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
  local dmarks = api.nvim_buf_get_extmarks(bufnr, ns_rm, 0, -1, {})
  for _, mark in ipairs(dmarks as {{integer, integer, integer}}) do
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

  -- Make sure these requires are done in the main event.
  -- See https://github.com/neovim/neovim/issues/15147
  local run_diff: function({string}, {string}, string, boolean): {Hunk}
  if config.diff_opts.internal then
    run_diff = require('gitsigns.diff_int').run_diff
  else
    run_diff = require('gitsigns.diff_ext').run_diff
  end

  if not bcache.compare_text or config._refresh_staged_on_update then
    bcache.compare_text = git_obj:get_show_text(bcache:get_compare_rev())
  end

  bcache.hunks = run_diff(bcache.compare_text, buftext,
    config.diff_opts.algorithm, config.diff_opts.indent_heuristic)

  scheduler_if_buf_valid(bufnr)
  if gs_hunks.compare_heads(bcache.hunks, old_hunks) then
    local hunk_marks = gs_hunks.calc_hunkmarks(bcache.hunks)
    if config._extmark_signs then
      M.apply_hunkmarks(bufnr, bcache.hunk_marks, hunk_marks)
    else
      bcache.pending_signs = gs_hunks.process_hunkmarks(hunk_marks)

      -- Apply signs to the window. Other signs will be added by the decoration
      -- provider as they are drawn.
      M.apply_win_signs(bufnr)
    end
    bcache.hunk_marks = hunk_marks
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
M.update = throttle_by_id(update0) as function(integer, CacheEntry)

M.setup = function()
  M.update_debounced = debounce_trailing(config.update_debounce, void(M.update)) as function(integer)
end

M.setup_signs_and_highlights = function(redefine: boolean)
  -- Define signs
  for t, sign_name in pairs(signs.sign_map) do
    local cs = config.signs[t]

    signs.define(sign_name, {
      texthl = cs.hl,
      text   = config.signcolumn and cs.text or nil,
      numhl  = config.numhl      and cs.numhl,
      linehl = config.linehl     and cs.linehl
    }, redefine)

  end

  setup_highlights()
end

return M
