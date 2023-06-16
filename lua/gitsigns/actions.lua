local void = require('gitsigns.async').void
local scheduler = require('gitsigns.async').scheduler

local config = require('gitsigns.config').config
local mk_repeatable = require('gitsigns.repeat').mk_repeatable
local popup = require('gitsigns.popup')
local util = require('gitsigns.util')
local manager = require('gitsigns.manager')
local git = require('gitsigns.git')
local run_diff = require('gitsigns.diff')

local gs_cache = require('gitsigns.cache')
local cache = gs_cache.cache

local Hunks = require('gitsigns.hunks')

local api = vim.api
local current_buf = api.nvim_get_current_buf

local M = {}

--- @class Gitsigns.CmdParams.Smods
--- @field vertical boolean
--- @field split 'aboveleft'|'belowright'|'topleft'|'botright'

--- @class Gitsigns.CmdParams
--- @field range integer
--- @field line1 integer
--- @field line2 integer
--- @field count integer
--- @field smods Gitsigns.CmdParams.Smods

-- Variations of functions from M which are used for the Gitsigns command
--- @type table<string,fun(args: table, params: Gitsigns.CmdParams)>
local C = {}

local CP = {}

local ns_inline = api.nvim_create_namespace('gitsigns_preview_inline')

local function complete_heads(arglead)
  local all =
    vim.fn.systemlist({ 'git', 'rev-parse', '--symbolic', '--branches', '--tags', '--remotes' })
  return vim.tbl_filter(function(x)
    return vim.startswith(x, arglead)
  end, all)
end

--- Toggle |gitsigns-config-signbooleancolumn|
---
--- Parameters:~
---     {value} boolean|nil Value to set toggle. If `nil`
---     the toggle value is inverted.
---
--- Returns:~
---     Current value of |gitsigns-config-signcolumn|
M.toggle_signs = function(value)
  if value ~= nil then
    config.signcolumn = value
  else
    config.signcolumn = not config.signcolumn
  end
  M.refresh()
  return config.signcolumn
end

--- Toggle |gitsigns-config-numhl|
---
--- Parameters:~
---     {value} boolean|nil Value to set toggle. If `nil`
---     the toggle value is inverted.
---
--- Returns:~
---     Current value of |gitsigns-config-numhl|
M.toggle_numhl = function(value)
  if value ~= nil then
    config.numhl = value
  else
    config.numhl = not config.numhl
  end
  M.refresh()
  return config.numhl
end

--- Toggle |gitsigns-config-linehl|
---
--- Parameters:~
---     {value} boolean|nil Value to set toggle. If `nil`
---     the toggle value is inverted.
---
--- Returns:~
---     Current value of |gitsigns-config-linehl|
M.toggle_linehl = function(value)
  if value ~= nil then
    config.linehl = value
  else
    config.linehl = not config.linehl
  end
  M.refresh()
  return config.linehl
end

--- Toggle |gitsigns-config-word_diff|
---
--- Parameters:~
---     {value} boolean|nil Value to set toggle. If `nil`
---     the toggle value is inverted.
---
--- Returns:~
---     Current value of |gitsigns-config-word_diff|
M.toggle_word_diff = function(value)
  if value ~= nil then
    config.word_diff = value
  else
    config.word_diff = not config.word_diff
  end
  -- Don't use refresh() to avoid flicker
  api.nvim__buf_redraw_range(0, vim.fn.line('w0') - 1, vim.fn.line('w$'))
  return config.word_diff
end

--- Toggle |gitsigns-config-current_line_blame|
---
--- Parameters:~
---     {value} boolean|nil Value to set toggle. If `nil`
---     the toggle value is inverted.
---
--- Returns:~
---     Current value of |gitsigns-config-current_line_blame|
M.toggle_current_line_blame = function(value)
  if value ~= nil then
    config.current_line_blame = value
  else
    config.current_line_blame = not config.current_line_blame
  end
  M.refresh()
  return config.current_line_blame
end

--- Toggle |gitsigns-config-show_deleted|
---
--- Parameters:~
---     {value} boolean|nil Value to set toggle. If `nil`
---     the toggle value is inverted.
---
--- Returns:~
---     Current value of |gitsigns-config-show_deleted|
M.toggle_deleted = function(value)
  if value ~= nil then
    config.show_deleted = value
  else
    config.show_deleted = not config.show_deleted
  end
  M.refresh()
  return config.show_deleted
end

local function get_cursor_hunk(bufnr, hunks)
  bufnr = bufnr or current_buf()

  if not hunks then
    hunks = {}
    vim.list_extend(hunks, cache[bufnr].hunks or {})
    vim.list_extend(hunks, cache[bufnr].hunks_staged or {})
  end

  local lnum = api.nvim_win_get_cursor(0)[1]
  return Hunks.find_hunk(lnum, hunks)
end

--- @param bufnr integer
local function update(bufnr)
  manager.update(bufnr)
  scheduler()
  if vim.wo.diff then
    require('gitsigns.diffthis').update(bufnr)
  end
end

local function get_range(params)
  local range --- @type {[1]: integer, [2]: integer}?
  if params.range > 0 then
    range = { params.line1, params.line2 }
  end
  return range
end

--- @param bufnr integer
--- @param bcache Gitsigns.CacheEntry
--- @param greedy? boolean
--- @param staged? boolean
--- @return Gitsigns.Hunk.Hunk[]? hunks
local function get_hunks(bufnr, bcache, greedy, staged)
  local hunks --- @type Gitsigns.Hunk.Hunk[]

  if greedy then
    -- Re-run the diff without linematch
    local buftext = util.buf_lines(bufnr)
    local text --- @type string[]?
    if staged then
      text = bcache.compare_text_head
    else
      text = bcache.compare_text
    end
    if not text then
      return
    end
    hunks = run_diff(text, buftext, false)
    scheduler()
    return hunks
  end

  if staged then
    return bcache.hunks_staged
  end

  return bcache.hunks
end

--- @param bufnr integer
--- @param range? {[1]: integer, [2]: integer}
--- @param greedy? boolean
--- @param staged? boolean
--- @return Gitsigns.Hunk.Hunk
local function get_hunk(bufnr, range, greedy, staged)
  local bcache = cache[bufnr]
  local hunks = get_hunks(bufnr, bcache, greedy, staged)
  local hunk --- @type Gitsigns.Hunk.Hunk
  if range then
    table.sort(range)
    local top, bot = range[1], range[2]
    hunk = Hunks.create_partial_hunk(hunks, top, bot)
    hunk.added.lines = api.nvim_buf_get_lines(bufnr, top - 1, bot, false)
    hunk.removed.lines = vim.list_slice(
      bcache.compare_text,
      hunk.removed.start,
      hunk.removed.start + hunk.removed.count - 1
    )
  else
    hunk = get_cursor_hunk(bufnr, hunks)
  end
  return hunk
end

--- Stage the hunk at the cursor position, or all lines in the
--- given range. If {range} is provided, all lines in the given
--- range are staged. This supports partial-hunks, meaning if a
--- range only includes a portion of a particular hunk, only the
--- lines within the range will be staged.
---
--- Attributes: ~
---     {async}
---
--- Parameters:~
---     {range} table|nil List-like table of two integers making
---             up the line range from which you want to stage the hunks.
---             If running via command line, then this is taken from the
---             command modifiers.
---     {opts}  table|nil Additional options:
---             • {greedy}: (boolean)
---               Stage all contiguous hunks. Only useful if 'diff_opts'
---               contains `linematch`. Defaults to `true`.
---
M.stage_hunk = mk_repeatable(void(function(range, opts)
  opts = opts or {}
  local bufnr = current_buf()
  local bcache = cache[bufnr]
  if not bcache then
    return
  end

  if not util.path_exists(bcache.file) then
    print('Error: Cannot stage lines. Please add the file to the working tree.')
    return
  end

  local hunk = get_hunk(bufnr, range, opts.greedy ~= false, false)

  local invert = false
  if not hunk then
    invert = true
    hunk = get_hunk(bufnr, range, opts.greedy ~= false, true)
  end

  if not hunk then
    return
  end

  bcache.git_obj:stage_hunks({ hunk }, invert)

  table.insert(bcache.staged_diffs, hunk)

  bcache:invalidate()
  update(bufnr)
end))

C.stage_hunk = function(_, params)
  M.stage_hunk(get_range(params))
end

--- Reset the lines of the hunk at the cursor position, or all
--- lines in the given range. If {range} is provided, all lines in
--- the given range are reset. This supports partial-hunks,
--- meaning if a range only includes a portion of a particular
--- hunk, only the lines within the range will be reset.
---
--- Parameters:~
---     {range} table|nil List-like table of two integers making
---             up the line range from which you want to reset the hunks.
---             If running via command line, then this is taken from the
---             command modifiers.
---     {opts}  table|nil Additional options:
---             • {greedy}: (boolean)
---               Stage all contiguous hunks. Only useful if 'diff_opts'
---               contains `linematch`. Defaults to `true`.
---
M.reset_hunk = mk_repeatable(void(function(range, opts)
  opts = opts or {}
  local bufnr = current_buf()
  local bcache = cache[bufnr]
  if not bcache then
    return
  end

  local hunk = get_hunk(bufnr, range, opts.greedy ~= false, false)

  if not hunk then
    return
  end

  local lstart, lend ---@type integer, integer
  if hunk.type == 'delete' then
    lstart = hunk.added.start
    lend = hunk.added.start
  else
    lstart = hunk.added.start - 1
    lend = hunk.added.start - 1 + hunk.added.count
  end
  util.set_lines(bufnr, lstart, lend, hunk.removed.lines)
end))

C.reset_hunk = function(_, params)
  M.reset_hunk(get_range(params))
end

--- Reset the lines of all hunks in the buffer.
M.reset_buffer = function()
  local bufnr = current_buf()
  local bcache = cache[bufnr]
  if not bcache then
    return
  end

  util.set_lines(bufnr, 0, -1, bcache.compare_text)
end

--- Undo the last call of stage_hunk().
---
--- Note: only the calls to stage_hunk() performed in the current
--- session can be undone.
---
--- Attributes: ~
---     {async}
M.undo_stage_hunk = void(function()
  local bufnr = current_buf()
  local bcache = cache[bufnr]
  if not bcache then
    return
  end

  local hunk = table.remove(bcache.staged_diffs)
  if not hunk then
    print('No hunks to undo')
    return
  end

  bcache.git_obj:stage_hunks({ hunk }, true)
  bcache:invalidate()
  update(bufnr)
end)

--- Stage all hunks in current buffer.
---
--- Attributes: ~
---     {async}
M.stage_buffer = void(function()
  local bufnr = current_buf()

  local bcache = cache[bufnr]
  if not bcache then
    return
  end

  -- Only process files with existing hunks
  local hunks = bcache.hunks
  if #hunks == 0 then
    print('No unstaged changes in file to stage')
    return
  end

  if not util.path_exists(bcache.git_obj.file) then
    print('Error: Cannot stage file. Please add it to the working tree.')
    return
  end

  bcache.git_obj:stage_hunks(hunks)

  for _, hunk in ipairs(hunks) do
    table.insert(bcache.staged_diffs, hunk)
  end

  bcache:invalidate()
  update(bufnr)
end)

--- Unstage all hunks for current buffer in the index. Note:
--- Unlike |gitsigns.undo_stage_hunk()| this doesn't simply undo
--- stages, this runs an `git reset` on current buffers file.
---
--- Attributes: ~
---     {async}
M.reset_buffer_index = void(function()
  local bufnr = current_buf()
  local bcache = cache[bufnr]
  if not bcache then
    return
  end

  -- `bcache.staged_diffs` won't contain staged changes outside of current
  -- neovim session so signs added from this unstage won't be complete They will
  -- however be fixed by gitdir watcher and properly updated We should implement
  -- some sort of initial population from git diff, after that this function can
  -- be improved to check if any staged hunks exists and it can undo changes
  -- using git apply line by line instead of resetting whole file
  bcache.staged_diffs = {}

  bcache.git_obj:unstage_file()

  bcache:invalidate()
  update(bufnr)
end)

local function process_nav_opts(opts)
  -- show navigation message
  if opts.navigation_message == nil then
    opts.navigation_message = not vim.opt.shortmess:get().S
  end

  -- wrap around
  if opts.wrap == nil then
    opts.wrap = vim.opt.wrapscan:get()
  end

  if opts.foldopen == nil then
    opts.foldopen = vim.tbl_contains(vim.opt.foldopen:get(), 'search')
  end

  if opts.greedy == nil then
    opts.greedy = true
  end
end

-- Defer function to the next main event
--- @param fn function
local function defer(fn)
  if vim.in_fast_event() then
    vim.schedule(fn)
  else
    vim.defer_fn(fn, 1)
  end
end

--- @param bufnr integer
--- @return boolean
local function has_preview_inline(bufnr)
  return #api.nvim_buf_get_extmarks(bufnr, ns_inline, 0, -1, { limit = 1 }) > 0
end

local nav_hunk = void(function(opts)
  process_nav_opts(opts)
  local bufnr = current_buf()
  local bcache = cache[bufnr]
  if not bcache then
    return
  end

  local hunks = {}
  vim.list_extend(hunks, get_hunks(bufnr, bcache, opts.greedy, false) or {})
  local hunks_head = get_hunks(bufnr, bcache, opts.greedy, true) or {}
  vim.list_extend(hunks, Hunks.filter_common(hunks_head, bcache.hunks) or {})

  if not hunks or vim.tbl_isempty(hunks) then
    if opts.navigation_message then
      api.nvim_echo({ { 'No hunks', 'WarningMsg' } }, false, {})
    end
    return
  end
  local line = api.nvim_win_get_cursor(0)[1]

  local hunk, index = Hunks.find_nearest_hunk(line, hunks, opts.forwards, opts.wrap)

  if hunk == nil then
    if opts.navigation_message then
      api.nvim_echo({ { 'No more hunks', 'WarningMsg' } }, false, {})
    end
    return
  end

  local row = opts.forwards and hunk.added.start or hunk.vend
  if row then
    -- Handle topdelete
    if row == 0 then
      row = 1
    end
    vim.cmd([[ normal! m' ]]) -- add current cursor position to the jump list
    api.nvim_win_set_cursor(0, { row, 0 })
    if opts.foldopen then
      vim.cmd('silent! foldopen!')
    end
    if opts.preview or popup.is_open('hunk') ~= nil then
      -- Use defer so the cursor change can settle, otherwise the popup might
      -- appear in the old position
      defer(function()
        -- Close the popup in case one is open which will cause it to focus the
        -- popup
        popup.close('hunk')
        M.preview_hunk()
      end)
    elseif has_preview_inline(bufnr) then
      defer(M.preview_hunk_inline)
    end

    if index ~= nil and opts.navigation_message then
      api.nvim_echo({ { string.format('Hunk %d of %d', index, #hunks), 'None' } }, false, {})
    end
  end
end)

--- Jump to the next hunk in the current buffer. If a hunk preview
--- (popup or inline) was previously opened, it will be re-opened
--- at the next hunk.
---
--- Parameters: ~
---     {opts}  table|nil Configuration table. Keys:
---             • {wrap}: (boolean)
---               Whether to loop around file or not. Defaults
---               to the value 'wrapscan'
---             • {navigation_message}: (boolean)
---               Whether to show navigation messages or not.
---               Looks at 'shortmess' for default behaviour.
---             • {foldopen}: (boolean)
---               Expand folds when navigating to a hunk which is
---               inside a fold. Defaults to `true` if 'foldopen'
---               contains `search`.
---             • {preview}: (boolean)
---               Automatically open preview_hunk() upon navigating
---               to a hunk.
---             • {greedy}: (boolean)
---               Only navigate between non-contiguous hunks. Only useful if
---               'diff_opts' contains `linematch`. Defaults to `true`.
M.next_hunk = function(opts)
  opts = opts or {}
  opts.forwards = true
  nav_hunk(opts)
end

--- Jump to the previous hunk in the current buffer. If a hunk preview
--- (popup or inline) was previously opened, it will be re-opened
--- at the previous hunk.
---
--- Parameters: ~
---     See |gitsigns.next_hunk()|.
M.prev_hunk = function(opts)
  opts = opts or {}
  opts.forwards = false
  nav_hunk(opts)
end

--- @param fmt {[1]: string, [2]: string}[][]
--- @param info table
--- @return {[1]: string, [2]: string}[][]
local function lines_format(fmt, info)
  --- @type {[1]: string, [2]: string}[][]
  local ret = vim.deepcopy(fmt)

  for _, line in ipairs(ret) do
    for _, s in ipairs(line) do
      s[1] = util.expand_format(s[1], info)
    end
  end

  return ret
end

--- @param hunk Gitsigns.Hunk.Hunk
--- @param hl string
--- @return table[]
local function hlmarks_for_hunk(hunk, hl)
  local hls = {} --- @type table[]

  local removed, added = hunk.removed, hunk.added

  if hl then
    hls[#hls + 1] = {
      hl_group = hl,
      start_row = 0,
      end_row = removed.count + added.count,
    }
  end

  hls[#hls + 1] = {
    hl_group = 'GitSignsDeletePreview',
    start_row = 0,
    end_row = removed.count,
  }

  hls[#hls + 1] = {
    hl_group = 'GitSignsAddPreview',
    start_row = removed.count,
    end_row = removed.count + added.count,
  }

  if config.diff_opts.internal then
    local removed_regions, added_regions =
      require('gitsigns.diff_int').run_word_diff(removed.lines, added.lines)
    for _, region in ipairs(removed_regions) do
      hls[#hls + 1] = {
        hl_group = 'GitSignsDeleteInline',
        start_row = region[1] - 1,
        start_col = region[3],
        end_col = region[4],
      }
    end
    for _, region in ipairs(added_regions) do
      hls[#hls + 1] = {
        hl_group = 'GitSignsAddInline',
        start_row = region[1] + removed.count - 1,
        start_col = region[3],
        end_col = region[4],
      }
    end
  end

  return hls
end

--- @param fmt {[1]: string, [2]: string}[][]
--- @param hunk Gitsigns.Hunk.Hunk
local function insert_hunk_hlmarks(fmt, hunk)
  for _, line in ipairs(fmt) do
    for _, s in ipairs(line) do
      local hl = s[2]
      if s[1] == '<hunk>' and type(hl) == 'string' then
        s[2] = hlmarks_for_hunk(hunk, hl)
      end
    end
  end
end

local function noautocmd(f)
  return function()
    local ei = vim.o.eventignore
    vim.o.eventignore = 'all'
    f()
    vim.o.eventignore = ei
  end
end

--- Preview the hunk at the cursor position in a floating
--- window. If the preview is already open, calling this
--- will cause the window to get focus.
M.preview_hunk = noautocmd(function()
  -- Wrap in noautocmd so vim-repeat continues to work

  if popup.focus_open('hunk') then
    return
  end

  local bufnr = current_buf()

  local hunk, index = get_cursor_hunk(bufnr)

  if not hunk then
    return
  end

  local lines_fmt = {
    { { 'Hunk <hunk_no> of <num_hunks>', 'Title' } },
    { { '<hunk>', 'NormalFloat' } },
  }

  insert_hunk_hlmarks(lines_fmt, hunk)

  local lines_spec = lines_format(lines_fmt, {
    hunk_no = index,
    num_hunks = #cache[bufnr].hunks,
    hunk = Hunks.patch_lines(hunk, vim.bo[bufnr].fileformat),
  })

  popup.create(lines_spec, config.preview_config, 'hunk')
end)

local function clear_preview_inline(bufnr)
  api.nvim_buf_clear_namespace(bufnr, ns_inline, 0, -1)
end

--- Preview the hunk at the cursor position inline in the buffer.
M.preview_hunk_inline = function()
  local bufnr = current_buf()

  local hunk = get_cursor_hunk(bufnr)

  if not hunk then
    return
  end

  clear_preview_inline(bufnr)

  local winid ---@type integer
  manager.show_added(bufnr, ns_inline, hunk)
  if config._inline2 then
    if hunk.removed.count > 0 then
      winid = manager.show_deleted_in_float(bufnr, ns_inline, hunk)
    end
  else
    manager.show_deleted(bufnr, ns_inline, hunk)
  end

  api.nvim_create_autocmd({ 'CursorMoved', 'InsertEnter' }, {
    buffer = bufnr,
    desc = 'Clear gitsigns inline preview',
    callback = function()
      if winid then
        pcall(api.nvim_win_close, winid, true)
      end
      clear_preview_inline(bufnr)
    end,
    once = true,
  })

  -- Virtual lines will be hidden if cursor is on the top row, so automatically
  -- scroll the viewport.
  if api.nvim_win_get_cursor(0)[1] == 1 then
    local keys = hunk.removed.count .. '<C-y>'
    local cy = api.nvim_replace_termcodes(keys, true, false, true)
    api.nvim_feedkeys(cy, 'n', false)
  end
end

--- Select the hunk under the cursor.
M.select_hunk = function()
  local hunk = get_cursor_hunk()
  if not hunk then
    return
  end

  vim.cmd('normal! ' .. hunk.added.start .. 'GV' .. hunk.vend .. 'G')
end

--- Get hunk array for specified buffer.
---
--- Parameters: ~
---     {bufnr} integer: Buffer number, if not provided (or 0)
---             will use current buffer.
---
--- Return: ~
---    Array of hunk objects. Each hunk object has keys:
---      • `"type"`: String with possible values: "add", "change",
---        "delete"
---      • `"head"`: Header that appears in the unified diff
---        output.
---      • `"lines"`: Line contents of the hunks prefixed with
---        either `"-"` or `"+"`.
---      • `"removed"`: Sub-table with fields:
---        • `"start"`: Line number (1-based)
---        • `"count"`: Line count
---      • `"added"`: Sub-table with fields:
---        • `"start"`: Line number (1-based)
---        • `"count"`: Line count
M.get_hunks = function(bufnr)
  bufnr = bufnr or current_buf()
  if not cache[bufnr] then
    return
  end
  local ret = {}
  -- TODO(lewis6991): allow this to accept a greedy option
  for _, h in ipairs(cache[bufnr].hunks or {}) do
    ret[#ret + 1] = {
      head = h.head,
      lines = Hunks.patch_lines(h, vim.bo[bufnr].fileformat),
      type = h.type,
      added = h.added,
      removed = h.removed,
    }
  end
  return ret
end

--- @param repo Gitsigns.Repo
--- @param info Gitsigns.BlameInfo
--- @return Gitsigns.Hunk.Hunk?, integer?, integer
local function get_blame_hunk(repo, info)
  local a = {}
  -- If no previous so sha of blame added the file
  if info.previous then
    a = repo:get_show_text(info.previous_sha .. ':' .. info.previous_filename)
  end
  local b = repo:get_show_text(info.sha .. ':' .. info.filename)
  local hunks = run_diff(a, b, false)
  local hunk, i = Hunks.find_hunk(info.orig_lnum, hunks)
  return hunk, i, #hunks
end

local function create_blame_fmt(is_committed, full)
  if not is_committed then
    return {
      { { '<author>', 'Label' } },
    }
  end

  local header = {
    { '<abbrev_sha> ', 'Directory' },
    { '<author> ', 'MoreMsg' },
    { '(<author_time:%Y-%m-%d %H:%M>)', 'Label' },
    { ':', 'NormalFloat' },
  }

  if full then
    return {
      header,
      { { '<body>', 'NormalFloat' } },
      { { 'Hunk <hunk_no> of <num_hunks>', 'Title' }, { ' <hunk_head>', 'LineNr' } },
      { { '<hunk>', 'NormalFloat' } },
    }
  end

  return {
    header,
    { { '<summary>', 'NormalFloat' } },
  }
end

--- Run git blame on the current line and show the results in a
--- floating window. If already open, calling this will cause the
--- window to get focus.
---
--- Parameters: ~
---     {opts}   (table|nil):
---              Additional options:
---              • {full}: (boolean)
---                Display full commit message with hunk.
---              • {ignore_whitespace}: (boolean)
---                Ignore whitespace when running blame.
---
--- Attributes: ~
---     {async}
M.blame_line = void(function(opts)
  if popup.focus_open('blame') then
    return
  end

  opts = opts or {}

  local bufnr = current_buf()
  local bcache = cache[bufnr]
  if not bcache then
    return
  end

  local loading = vim.defer_fn(function()
    popup.create({ { { 'Loading...', 'Title' } } }, config.preview_config)
  end, 1000)

  scheduler()
  local buftext = util.buf_lines(bufnr)
  local fileformat = vim.bo[bufnr].fileformat
  local lnum = api.nvim_win_get_cursor(0)[1]
  local result = bcache.git_obj:run_blame(buftext, lnum, opts.ignore_whitespace)
  pcall(function()
    loading:close()
  end)

  assert(result)

  local is_committed = result.sha and tonumber('0x' .. result.sha) ~= 0

  local blame_fmt = create_blame_fmt(is_committed, opts.full)

  if is_committed and opts.full then
    result.body = bcache.git_obj:command({ 'show', '-s', '--format=%B', result.sha })

    local hunk

    hunk, result.hunk_no, result.num_hunks = get_blame_hunk(bcache.git_obj.repo, result)

    result.hunk = Hunks.patch_lines(hunk, fileformat)
    result.hunk_head = hunk.head
    insert_hunk_hlmarks(blame_fmt, hunk)
  end

  scheduler()

  popup.create(lines_format(blame_fmt, result), config.preview_config, 'blame')
end)

local function update_buf_base(buf, bcache, base)
  bcache.base = base
  bcache:invalidate()
  update(buf)
end

--- Change the base revision to diff against. If {base} is not
--- given, then the original base is used. If {global} is given
--- and true, then change the base revision of all buffers,
--- including any new buffers.
---
--- Attributes: ~
---     {async}
---
--- Parameters:~
---     {base} string|nil The object/revision to diff against.
---     {global} boolean|nil Change the base of all buffers.
---
--- Examples: >
---   " Change base to 1 commit behind head
---   :lua require('gitsigns').change_base('HEAD~1')
---
---   " Also works using the Gitsigns command
---   :Gitsigns change_base HEAD~1
---
---   " Other variations
---   :Gitsigns change_base ~1
---   :Gitsigns change_base ~
---   :Gitsigns change_base ^
---
---   " Commits work too
---   :Gitsigns change_base 92eb3dd
---
---   " Revert to original base
---   :Gitsigns change_base
--- <
---
--- For a more complete list of ways to specify bases, see
--- |gitsigns-revision|.
M.change_base = void(function(base, global)
  base = util.calc_base(base)

  if global then
    config.base = base

    for bufnr, bcache in pairs(cache) do
      update_buf_base(bufnr, bcache, base)
    end
  else
    local bufnr = current_buf()
    local bcache = cache[bufnr]
    if not bcache then
      return
    end

    update_buf_base(bufnr, bcache, base)
  end
end)

C.change_base = function(args, _)
  M.change_base(args[1], (args[2] or args.global))
end

CP.change_base = complete_heads

--- Reset the base revision to diff against back to the
--- index.
---
--- Alias for `change_base(nil, {global})` .
M.reset_base = function(global)
  M.change_base(nil, global)
end

C.reset_base = function(args, _)
  M.change_base(nil, (args[1] or args.global))
end

--- Perform a |vimdiff| on the given file with {base} if it is
--- given, or with the currently set base (index by default).
---
--- If {base} is the index, then the opened buffer is editable and
--- any written changes will update the index accordingly.
---
--- Parameters: ~
---     {base}   (string|nil): Revision to diff against. Defaults
---              to index.
---     {opts}   (table|nil):
---              Additional options:
---              • {vertical}: {boolean}. Split window vertically. Defaults to
---              config.diff_opts.vertical. If running via command line, then
---              this is taken from the command modifiers.
---              • {split}: {string}. One of: 'aboveleft', 'belowright',
---              'botright', 'rightbelow', 'leftabove', 'topleft'. Defaults to
---              'aboveleft'. If running via command line, then this is taken
---              from the command modifiers.
---
--- Examples: >
---   " Diff against the index
---   :Gitsigns diffthis
---
---   " Diff against the last commit
---   :Gitsigns diffthis ~1
--- <
---
--- For a more complete list of ways to specify bases, see
--- |gitsigns-revision|.
---
--- Attributes: ~
---     {async}
M.diffthis = function(base, opts)
  -- TODO(lewis6991): can't pass numbers as strings from the command line
  if base ~= nil then
    base = tostring(base)
  end
  opts = opts or {}
  local diffthis = require('gitsigns.diffthis')
  if not opts.vertical then
    opts.vertical = config.diff_opts.vertical
  end
  diffthis.diffthis(base, opts)
end

C.diffthis = function(args, params)
  -- TODO(lewis6991): validate these
  local opts = {
    vertical = args.vertical,
    split = args.split,
  }

  if params.smods then
    if params.smods.split ~= '' and opts.split == nil then
      opts.split = params.smods.split
    end
    if opts.vertical == nil then
      opts.vertical = params.smods.vertical
    end
  end

  M.diffthis(args[1], opts)
end

CP.diffthis = complete_heads

-- C.test = function(pos_args: {any}, named_args: {string:any}, params: api.UserCmdParams)
--    print('POS ARGS:', vim.inspect(pos_args))
--    print('NAMED ARGS:', vim.inspect(named_args))
--    print('PARAMS:', vim.inspect(params))
-- end

--- Show revision {base} of the current file, if it is given, or
--- with the currently set base (index by default).
---
--- If {base} is the index, then the opened buffer is editable and
--- any written changes will update the index accordingly.
---
--- Examples: >
---   " View the index version of the file
---   :Gitsigns show
---
---   " View revision of file in the last commit
---   :Gitsigns show ~1
--- <
---
--- For a more complete list of ways to specify bases, see
--- |gitsigns-revision|.
---
--- Attributes: ~
---     {async}
M.show = function(revision)
  local diffthis = require('gitsigns.diffthis')
  diffthis.show(revision)
end

CP.show = complete_heads

--- @param buf_or_filename string|integer
--- @param hunks Gitsigns.Hunk.Hunk[]
--- @param qflist table[]?
local function hunks_to_qflist(buf_or_filename, hunks, qflist)
  for i, hunk in ipairs(hunks) do
    qflist[#qflist + 1] = {
      bufnr = type(buf_or_filename) == 'number' and buf_or_filename or nil,
      filename = type(buf_or_filename) == 'string' and buf_or_filename or nil,
      lnum = hunk.added.start,
      text = string.format('Lines %d-%d (%d/%d)', hunk.added.start, hunk.vend, i, #hunks),
    }
  end
end

---@param target 'all'|'attached'|integer
---@return table[]?
local function buildqflist(target)
  target = target or current_buf()
  if target == 0 then
    target = current_buf()
  end
  local qflist = {} ---@type table[]

  if type(target) == 'number' then
    local bufnr = target
    if not cache[bufnr] then
      return
    end
    hunks_to_qflist(bufnr, cache[bufnr].hunks, qflist)
  elseif target == 'attached' then
    for bufnr, bcache in pairs(cache) do
      hunks_to_qflist(bufnr, bcache.hunks, qflist)
    end
  elseif target == 'all' then
    local repos = {} --- @type table<string,Gitsigns.Repo>
    for _, bcache in pairs(cache) do
      local repo = bcache.git_obj.repo
      if not repos[repo.gitdir] then
        repos[repo.gitdir] = repo
      end
    end

    local repo = git.Repo.new(assert(vim.loop.cwd()))
    if not repos[repo.gitdir] then
      repos[repo.gitdir] = repo
    end

    for _, r in pairs(repos) do
      for _, f in ipairs(r:files_changed()) do
        local f_abs = r.toplevel .. '/' .. f
        local stat = vim.loop.fs_stat(f_abs)
        if stat and stat.type == 'file' then
          local a = r:get_show_text(':0:' .. f)
          scheduler()
          local hunks = run_diff(a, util.file_lines(f_abs))
          hunks_to_qflist(f_abs, hunks, qflist)
        end
      end
    end
  end
  return qflist
end

--- Populate the quickfix list with hunks. Automatically opens the
--- quickfix window.
---
--- Attributes: ~
---     {async}
---
--- Parameters: ~
---     {target} (integer or string):
---              Specifies which files hunks are collected from.
---              Possible values.
---              • [integer]: The buffer with the matching buffer
---                number. `0` for current buffer (default).
---              • `"attached"`: All attached buffers.
---              • `"all"`: All modified files for each git
---                directory of all attached buffers in addition
---                to the current working directory.
---     {opts}   (table|nil):
---              Additional options:
---              • {use_location_list}: (boolean)
---                Populate the location list instead of the
---                quickfix list. Default to `false`.
---              • {nr}: (integer)
---                Window number or ID when using location list.
---                Expand folds when navigating to a hunk which is
---                inside a fold. Defaults to `0`.
---              • {open}: (boolean)
---                Open the quickfix/location list viewer.
---                Defaults to `true`.
M.setqflist = void(function(target, opts)
  opts = opts or {}
  if opts.open == nil then
    opts.open = true
  end
  local qfopts = {
    items = buildqflist(target),
    title = 'Hunks',
  }
  scheduler()
  if opts.use_location_list then
    local nr = opts.nr or 0
    vim.fn.setloclist(nr, {}, ' ', qfopts)
    if opts.open then
      if config.trouble then
        require('trouble').open('loclist')
      else
        vim.cmd([[lopen]])
      end
    end
  else
    vim.fn.setqflist({}, ' ', qfopts)
    if opts.open then
      if config.trouble then
        require('trouble').open('quickfix')
      else
        vim.cmd([[copen]])
      end
    end
  end
end)

--- Populate the location list with hunks. Automatically opens the
--- location list window.
---
--- Alias for: `setqflist({target}, { use_location_list = true, nr = {nr} }`
---
--- Attributes: ~
---     {async}
---
--- Parameters: ~
---     {nr}     (integer): Window number or the |window-ID|.
---              `0` for the current window (default).
---     {target} (integer or string): See |gitsigns.setqflist()|.
M.setloclist = function(nr, target)
  M.setqflist(target, {
    nr = nr,
    use_location_list = true,
  })
end

--- Get all the available line specific actions for the current
--- buffer at the cursor position.
---
--- Return: ~
---     Dictionary of action name to function which when called
---     performs action.
M.get_actions = function()
  local bufnr = current_buf()
  local bcache = cache[bufnr]
  if not bcache then
    return
  end
  local hunk = get_cursor_hunk()

  --- @type function[]
  local actions_l = {}

  local function add_action(action)
    actions_l[#actions_l + 1] = action
  end

  if hunk then
    add_action('stage_hunk')
    add_action('reset_hunk')
    add_action('preview_hunk')
    add_action('select_hunk')
  else
    add_action('blame_line')
  end

  if not vim.tbl_isempty(bcache.staged_diffs) then
    add_action('undo_stage_hunk')
  end

  local actions = {}
  for _, a in ipairs(actions_l) do
    actions[a] = (M)[a]
  end

  return actions
end

--- Refresh all buffers.
---
--- Attributes: ~
---     {async}
M.refresh = void(function()
  manager.reset_signs()
  require('gitsigns.highlight').setup_highlights()
  require('gitsigns.current_line_blame').setup()
  for k, v in pairs(cache) do
    v:invalidate()
    manager.update(k, v)
  end
end)

function M._get_cmd_func(name)
  return C[name]
end

function M._get_cmp_func(name)
  return CP[name]
end

return M
