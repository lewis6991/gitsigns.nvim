local void      = require('plenary.async.async').void
local scheduler = require('plenary.async.util').scheduler

local Status        = require("gitsigns.status")
local config        = require('gitsigns.config').config
local mk_repeatable = require('gitsigns.repeat').mk_repeatable
local popup         = require('gitsigns.popup')
local signs         = require('gitsigns.signs')
local util          = require('gitsigns.util')
local manager       = require('gitsigns.manager')
local git           = require('gitsigns.git')
local warn          = require('gitsigns.message').warn

local gs_cache       = require('gitsigns.cache')
local cache          = gs_cache.cache
local CacheEntry     = gs_cache.CacheEntry

local gs_hunks = require('gitsigns.hunks')
local Hunk = gs_hunks.Hunk
local Hunk_Public = gs_hunks.Hunk_Public

local api = vim.api
local current_buf = api.nvim_get_current_buf

local record NavHunkOpts
  forwards: boolean
  wrap: boolean
  navigation_message: boolean
  foldopen: boolean
end

local record M
  stage_hunk         : function -- function()
  undo_stage_hunk    : function -- function()
  reset_hunk         : function -- function(bufnr: integer, hunk: Hunk)

  stage_buffer       : function -- function()
  reset_buffer       : function -- function()
  reset_buffer_index : function -- function()

  next_hunk          : function(NavHunkOpts)
  prev_hunk          : function(NavHunkOpts)
  preview_hunk       : function()
  select_hunk        : function()
  get_hunks          : function(bufnr: integer): {Hunk_Public}

  blame_line         : function -- function()
  change_base        : function(base: string, global: boolean)
  reset_base         : function(global: boolean)
  diffthis           : function -- function(base: string)

  record QFListOpts
    use_location_list: boolean
    nr: integer
    open: boolean
  end

  setqflist          : function(target:integer|string, opts: QFListOpts, callback: function)
  setloclist         : function(nr: integer, target:integer|string)

  user_range         : {integer, integer}

  get_actions        : function(bufnr: integer, lnum: integer)

  refresh            : function()
  toggle_signs       : function()
  toggle_numhl       : function()
  toggle_linehl      : function()
  toggle_word_diff   : function()
  toggle_current_line_blame : function()
  toggle_deleted     : function()
end

--- Toggle |gitsigns-config-signcolumn|
M.toggle_signs = function()
  config.signcolumn = not config.signcolumn
  M.refresh()
end

--- Toggle |gitsigns-config-numhl|
M.toggle_numhl = function()
  config.numhl = not config.numhl
  M.refresh()
end

--- Toggle |gitsigns-config-linehl|
M.toggle_linehl = function()
  config.linehl = not config.linehl
  M.refresh()
end

--- Toggle |gitsigns-config-word_diff|
M.toggle_word_diff = function()
  config.word_diff = not config.word_diff
  M.refresh()
end

--- Toggle |gitsigns-config-current_line_blame|
M.toggle_current_line_blame = function()
  config.current_line_blame = not config.current_line_blame
  M.refresh()
end

--- Toggle |gitsigns-config-show_deleted|
M.toggle_deleted = function()
  config.show_deleted = not config.show_deleted
  M.refresh()
end

local function get_cursor_hunk(bufnr: integer, hunks: {Hunk}): Hunk, integer
  bufnr = bufnr or current_buf()
  hunks = hunks or cache[bufnr].hunks

  local lnum = api.nvim_win_get_cursor(0)[1]
  return gs_hunks.find_hunk(lnum, hunks)
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
---     up the line range from which you want to stage the hunks.
M.stage_hunk = mk_repeatable(void(function(range: {integer, integer})
  range = range or M.user_range
  local bufnr = current_buf()
  local bcache = cache[bufnr]
  if not bcache then
    return
  end

  if not util.path_exists(bcache.file) then
    print("Error: Cannot stage lines. Please add the file to the working tree.")
    return
  end

  local hunk: Hunk

  if range then
    table.sort(range)
    local top, bot = range[1], range[2]
    hunk = gs_hunks.create_partial_hunk(bcache.hunks, top, bot)
    hunk.added.lines = api.nvim_buf_get_lines(bufnr, top-1, bot, false)
    hunk.removed.lines = vim.list_slice(
      bcache.compare_text,
      hunk.removed.start,
      hunk.removed.start + hunk.removed.count - 1
    )
  else
    hunk = get_cursor_hunk(bufnr, bcache.hunks)
  end

  if not hunk then
    return
  end

  bcache.git_obj:stage_hunks({hunk})

  table.insert(bcache.staged_diffs, hunk)

  bcache.compare_text = nil -- Invalidate

  local hunk_signs = gs_hunks.process_hunks({hunk})

  scheduler()

  -- If watch_gitdir is enabled then that will eventually kick in and update the
  -- signs, however for  smoother UX we can update the signs immediately without
  -- running a full diff.
  --
  -- We cannot update the status bar as that requires a full diff.
  if not bcache.base then
    for lnum, _ in pairs(hunk_signs) do
      signs.remove(bufnr, lnum)
    end
  end
  void(manager.update)(bufnr)
end))

--- Reset the lines of the hunk at the cursor position, or all
--- lines in the given range. If {range} is provided, all lines in
--- the given range are reset. This supports partial-hunks,
--- meaning if a range only includes a portion of a particular
--- hunk, only the lines within the range will be reset.
---
--- Parameters:~
---     {range} table|nil List-like table of two integers making
---     up the line range from which you want to reset the hunks.
M.reset_hunk = mk_repeatable(function(range: {integer, integer})
  range = range or M.user_range
  local bufnr = current_buf()
  local bcache = cache[bufnr]
  if not bcache then
    return
  end

  local hunk: Hunk

  if range then
    table.sort(range)
    local top, bot = range[1], range[2]
    hunk = gs_hunks.create_partial_hunk(bcache.hunks, top, bot)
    hunk.added.lines = api.nvim_buf_get_lines(bufnr, top-1, bot, false)
    hunk.removed.lines = vim.list_slice(
      bcache.compare_text,
      hunk.removed.start,
      hunk.removed.start + hunk.removed.count - 1
    )
  else
    hunk = get_cursor_hunk(bufnr)
  end

  if not hunk then
    return
  end

  local lstart, lend: integer, integer
  if hunk.type == 'delete' then
    lstart = hunk.start
    lend = hunk.start
  else
    lstart = hunk.start - 1
    lend = hunk.start - 1 + hunk.added.count
  end
  local lines = hunk.removed.lines
  api.nvim_buf_set_lines(bufnr, lstart, lend, false, lines)
end)

--- Reset the lines of all hunks in the buffer.
M.reset_buffer = function()
  local bufnr = current_buf()
  local bcache = cache[bufnr]
  if not bcache then
    return
  end

  api.nvim_buf_set_lines(bufnr, 0, -1, false, bcache:get_compare_text())
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
    print("No hunks to undo")
    return
  end

  bcache.git_obj:stage_hunks({hunk}, true)
  bcache.compare_text = nil -- Invalidate
  scheduler()
  if not bcache.base then
    signs.add(config, bufnr, gs_hunks.process_hunks({hunk}))
  end
  manager.update(bufnr)
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
    print("No unstaged changes in file to stage")
    return
  end

  if not util.path_exists(bcache.git_obj.file) then
    print("Error: Cannot stage file. Please add it to the working tree.")
    return
  end

  bcache.git_obj:stage_hunks(hunks)

  for _, hunk in ipairs(hunks) do
    table.insert(bcache.staged_diffs, hunk)
  end
  bcache.compare_text = nil -- Invalidate

  scheduler()
  if not bcache.base then
    signs.remove(bufnr)
  end
  Status:clear_diff(bufnr)
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
  -- using git apply line by line instead of reseting whole file
  local hunks = bcache.staged_diffs
  bcache.staged_diffs = {}

  bcache.git_obj:unstage_file()
  bcache.compare_text = nil -- Invalidate

  scheduler()
  if not bcache.base then
    signs.add(config, bufnr, gs_hunks.process_hunks(hunks))
  end
  void(manager.update)(bufnr)
end)

local function process_nav_opts(opts: NavHunkOpts)
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
end

local function nav_hunk(opts: NavHunkOpts)
  process_nav_opts(opts)
  local bcache = cache[current_buf()]
  if not bcache then
    return
  end

  local hunks = bcache.hunks
  if not hunks or vim.tbl_isempty(hunks) then
    if opts.navigation_message then
      vim.api.nvim_echo({{'No hunks', 'WarningMsg'}}, false, {})
    end
    return
  end
  local line = api.nvim_win_get_cursor(0)[1]

  local hunk, index = gs_hunks.find_nearest_hunk(line, hunks, opts.forwards, opts.wrap)

  if hunk == nil then
    if opts.navigation_message then
        vim.api.nvim_echo({{'No more hunks', 'WarningMsg'}}, false, {})
    end
    return
  end

  local row = opts.forwards and hunk.start or hunk.vend
  if row then
    -- Handle topdelete
    if row == 0 then
      row = 1
    end
    vim.cmd [[ normal! m' ]] -- add current cursor position to the jump list
    api.nvim_win_set_cursor(0, {row, 0})
    if opts.foldopen then
      vim.cmd('silent! foldopen!')
    end
    if pcall(api.nvim_buf_get_var, 0, '_gitsigns_preview_open') then
      vim.schedule(M.preview_hunk)
    end

    if index ~= nil and opts.navigation_message then
        vim.api.nvim_echo({{string.format('Hunk %d of %d', index, #hunks), 'None'}}, false, {})
    end

  end
end

--- Jump to the next hunk in the current buffer.
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
M.next_hunk = function(opts: NavHunkOpts)
  opts = opts or {}
  opts.forwards = true
  nav_hunk(opts)
end

--- Jump to the previous hunk in the current buffer.
---
--- Parameters: ~
---     See |gitsigns.next_hunk()|.
M.prev_hunk = function(opts: NavHunkOpts)
  opts = opts or {}
  opts.forwards = false
  nav_hunk(opts)
end

local function highlight_hunk_lines(bufnr: integer, offset: integer, hunk: Hunk)
  for i = 1, #hunk.removed.lines do
    api.nvim_buf_add_highlight(bufnr, -1, 'DiffRemoved', offset+i-1, 0, -1)
  end
  for i = 1, #hunk.added.lines do
    api.nvim_buf_add_highlight(bufnr, -1, 'DiffAdded', #hunk.removed.lines + offset+i-1, 0, -1)
  end

  if config.diff_opts.internal then
    local regions = require('gitsigns.diff_int').run_word_diff(hunk.removed.lines, hunk.added.lines)
    for _, region in ipairs(regions) do
      local line, scol, ecol = region[1], region[3], region[4]
      api.nvim_buf_add_highlight(bufnr, -1, 'TermCursor', line+offset-1, scol, ecol)
    end
  end
end

local function noautocmd(f: function()): function()
  return function()
    local ei = api.nvim_get_option('eventignore')
    api.nvim_set_option('eventignore', 'all')
    f()
    api.nvim_set_option('eventignore', ei)
  end
end

-- Strip '\r' from the EOL of each line only if all lines end with '\r'
local function strip_cr(xs0: {string}): {string}
  for i = 1, #xs0 do
    if xs0[i]:sub(-1) ~= '\r' then
      -- don't strip, return early
      return xs0
    end
  end
  -- all lines end with '\r', need to strip
  local xs = vim.deepcopy(xs0)
  for i = 1, #xs do
    xs[i] = xs[i]:sub(1, -2)
  end
  return xs
end

--- Preview the hunk at the cursor position in a floating
--- window.
M.preview_hunk = noautocmd(function()
  -- Wrap in noautocmd so vim-repeat continues to work
  local cbuf = current_buf()
  local bcache = cache[cbuf]
  local hunk, index = get_cursor_hunk(cbuf, bcache.hunks)

  if not hunk then return end

  local hlines = gs_hunks.patch_lines(hunk)
  if vim.bo[cbuf].fileformat == 'dos' then
    hlines = strip_cr(hlines)
  end

  local lines = {
    ('Hunk %d of %d'):format(index, #bcache.hunks),
    unpack(hlines)
  }

  local _, bufnr = popup.create(lines, config.preview_config)

  api.nvim_buf_add_highlight(bufnr, -1, 'Title', 0, 0, -1)

  api.nvim_buf_set_var(cbuf, '_gitsigns_preview_open', true)
  vim.cmd[[autocmd CursorMoved,CursorMovedI <buffer> ++once silent! unlet b:_gitsigns_preview_open]]

  local offset = #lines - hunk.removed.count - hunk.added.count
  highlight_hunk_lines(bufnr as integer, offset, hunk)
end)

--- Select the hunk under the cursor.
M.select_hunk = function()
  local hunk = get_cursor_hunk()
  if not hunk then return end

  vim.cmd('normal! '..hunk.start..'GV'..hunk.vend..'G')
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
M.get_hunks = function(bufnr: integer): {Hunk_Public}
  bufnr = current_buf()
  if not cache[bufnr] then return end
  local ret = {}
  for _, h in ipairs(cache[bufnr].hunks) do
    ret[#ret+1] = {
      head    = h.head,
      lines   = gs_hunks.patch_lines(h),
      type    = h.type,
      added   = h.added,
      removed = h.removed
    }
  end
  return ret
end

local function defer(duration: integer, callback: function()): vim.loop.Timer
  local timer = vim.loop.new_timer()
  timer:start(duration, 0, function()
    timer:stop()
    timer:close()
    vim.schedule_wrap(callback)()
  end)
  return timer
end

local function run_diff(a: {string}, b: {string}): {Hunk}
  local diff_opts = config.diff_opts
  local f: function({string}, {string}, string, boolean): {Hunk}
  if config.diff_opts.internal then
    f = require('gitsigns.diff_int').run_diff
  else
    f = require('gitsigns.diff_ext').run_diff
  end
  return f(a, b, diff_opts.algorithm, diff_opts.indent_heuristic)
end

local function get_blame_hunk(repo: git.Repo, info: git.BlameInfo): Hunk, integer, integer
  local a = {}
  -- If no previous so sha of blame added the file
  if info.previous then
    a = repo:get_show_text(info.previous_sha..':'..info.previous_filename)
  end
  local b = repo:get_show_text(info.sha..':'..info.filename)
  local hunks = run_diff(a, b)
  local hunk, i = gs_hunks.find_hunk(info.orig_lnum, hunks)
  return hunk, i, #hunks
end

local record BlameOpts
  full: boolean
  ignore_whitespace: boolean
end

--- Run git blame on the current line and show the results in a
--- floating window.
---
--- Parameters: ~
---     {opts}   (table|nil):
---              Additional options:
---              • {full}: (boolean)
---                Display full commit message
---              • {ignore_whitespace}: (boolean)
---                Ignore whitespace when running blame.
---
--- Attributes: ~
---     {async}
M.blame_line = void(function(opts: boolean | BlameOpts)
  local bufnr = current_buf()
  local bcache = cache[bufnr]
  if not bcache then return end

  local full: boolean
  local ignore_whitespace: boolean
  if opts is boolean then
    -- Remove after v0.4
    warn('Passing boolean as the first argument to blame_line is now deprecated; please pass an options table')
    full = opts
  else
    opts = opts or {}
    full = opts.full
    ignore_whitespace = opts.ignore_whitespace
  end

  local loading = defer(1000, function()
    popup.create({'Loading...'}, config.preview_config)
  end)

  scheduler()
  local buftext = util.buf_lines(bufnr)
  local lnum = api.nvim_win_get_cursor(0)[1]
  local result = bcache.git_obj:run_blame(buftext, lnum, ignore_whitespace)
  pcall(function()
    loading:close()
  end)

  local hunk, ihunk, nhunk: Hunk, integer, integer
  local lines: {string} = {}

  local highlights: {{string, integer, integer, integer}} = {}

  local function add_highlight(hlgroup: string, start: integer, length: integer)
    highlights[#highlights+1] = {hlgroup, #lines-1, start or 0, length or -1}
  end

  local is_committed = result.sha and tonumber('0x'..result.sha) ~= 0
  if is_committed then
    local commit_message = {}
    if full then
       commit_message = bcache.git_obj:command({ 'show', '-s', '--format=%B', result.sha })
       while commit_message[#commit_message] == '' do
          commit_message[#commit_message] = nil
       end
    else
       commit_message = {result.summary}
    end

    local date = os.date('%Y-%m-%d %H:%M', tonumber(result['author_time']))

    lines[#lines+1] = ('%s %s (%s):'):format(result.abbrev_sha, result.author, date)
    local p1 = #result.abbrev_sha
    local p2 = #result.author
    local p3 = #date

    add_highlight('Directory', 0      , p1)
    add_highlight('MoreMsg'  , p1+1   , p2)
    add_highlight('Label'    , p1+p2+2, p3+2)

    vim.list_extend(lines, commit_message)

    if full then
      hunk, ihunk, nhunk = get_blame_hunk(bcache.git_obj.repo, result)
    end
  else
    lines[#lines+1] = result.author
    add_highlight('ErrorMsg')
    if full then
      scheduler()
      hunk, ihunk = get_cursor_hunk(bufnr, bcache.hunks)
      nhunk = #bcache.hunks
    end
  end

  if hunk then
    lines[#lines+1] = ''
    lines[#lines+1] = ('Hunk %d of %d'):format(ihunk, nhunk)
    add_highlight('Title')
    vim.list_extend(lines, gs_hunks.patch_lines(hunk))
  end

  scheduler()
  local _, pbufnr = popup.create(lines, config.preview_config)

  for _, h in ipairs(highlights) do
    local hlgroup, line, start, length = h[1], h[2], h[3], h[4]
    api.nvim_buf_add_highlight(pbufnr, -1, hlgroup, line, start, start+length)
  end

  if hunk then
    local offset = #lines - hunk.removed.count - hunk.added.count
    highlight_hunk_lines(pbufnr, offset, hunk)
  end
end)

local function calc_base(base: string): string
  if base and base:sub(1, 1):match('[~\\^]') then
    base = 'HEAD'..base
  end
  return base
end

local function update_buf_base(buf: integer, bcache: CacheEntry, base: string)
    bcache.base = base
    bcache.compare_text = nil
    manager.update(buf, bcache)
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
M.change_base = void(function(base: string, global: boolean)
  base = calc_base(base)

  if global then
    config.base = base

    for buf,bcache in pairs(cache as {integer:CacheEntry}) do
      update_buf_base(buf, bcache, base)
    end
  else
    local buf = current_buf()
    local bcache = cache[buf]
    if not bcache then return end

    update_buf_base(buf, bcache, base)
  end
end)

--- Reset the base revision to diff against back to the
--- index.
---
--- Alias for `change_base(nil, {global})` .
M.reset_base = function(global: boolean)
  M.change_base(nil, global)
end

--- Perform a |vimdiff| on the given file with {base} if it is
--- given, or with the currently set base (index by default).
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
M.diffthis = void(function(base: string)
  local bufnr = current_buf()
  local bcache = cache[bufnr]
  if not bcache then return end

  if api.nvim_win_get_option(0, 'diff') then return end

  local ff = vim.bo[bufnr].fileformat

  local text: {string}
  local err: string
  local comp_rev = bcache:get_compare_rev(calc_base(base))

  if base then
    text, err = bcache.git_obj:get_show_text(comp_rev)
    if ff == 'dos' then
      text = strip_cr(text)
    end
    if err then
      print(err)
      return
    end
    scheduler()
  else
    text = bcache:get_compare_text()
  end

  local ft = api.nvim_buf_get_option(bufnr, 'filetype')

  local bufname = string.format(
    'gitsigns://%s/%s',
    bcache.git_obj.repo.gitdir,
    comp_rev..':'..bcache.git_obj.relpath
  )

  -- TDOD lewis6991 (27/05/21): Respect 'vertical' in diffopt
  vim.cmd("keepalt aboveleft vertical split "..bufname)

  local dbuf = current_buf()

  api.nvim_buf_set_option(dbuf, 'modifiable', true)
  api.nvim_buf_set_lines(dbuf, 0, -1, false, text)
  api.nvim_buf_set_option(dbuf, 'modifiable', false)

  api.nvim_buf_set_option(dbuf, 'filetype', ft)
  api.nvim_buf_set_option(dbuf, 'buftype', 'nowrite')

  vim.cmd(string.format('autocmd! WinClosed <buffer=%d> ++once call nvim_buf_delete(%d, {})', dbuf, dbuf))

  vim.cmd[[windo diffthis]]
end)

local function hunks_to_qflist(buf_or_filename: number|string, hunks: {Hunk}, qflist: {vim.fn.QFItem})
  for i, hunk in ipairs(hunks) do
    qflist[#qflist+1] = {
      bufnr    = buf_or_filename is number and (buf_or_filename as integer) or nil,
      filename = buf_or_filename is string and buf_or_filename or nil,
      lnum = hunk.start,
      text = string.format('Lines %d-%d (%d/%d)',
      hunk.start, hunk.vend, i, #hunks),
    }
  end
end

local function buildqflist(target: integer|string): {vim.fn.QFItem}
  target = target or current_buf()
  if target == 0 then target = current_buf() end
  local qflist: {vim.fn.QFItem} = {}

  if type(target) == 'number' then
    local bufnr = target as integer
    if not cache[bufnr] then return end
    hunks_to_qflist(bufnr, cache[bufnr].hunks, qflist)
  elseif target == 'attached' then
    for bufnr, bcache in pairs(cache as {integer:CacheEntry}) do
      hunks_to_qflist(bufnr, bcache.hunks, qflist)
    end
  elseif target == 'all' then
    local repos: {string:git.Repo} = {}
    for _, bcache in pairs(cache as {integer:CacheEntry}) do
      local repo = bcache.git_obj.repo
      if not repos[repo.gitdir] then
        repos[repo.gitdir] = repo
      end
    end

    local repo = git.Repo.new(vim.fn.getcwd())
    if not repos[repo.gitdir] then
      repos[repo.gitdir] = repo
    end

    for _, r in pairs(repos) do
      for _, f in ipairs(r:files_changed()) do
        local f_abs = r.toplevel..'/'..f
        local stat = vim.loop.fs_stat(f_abs)
        if stat and stat.type == 'file' then
          local a = r:get_show_text(':0:'..f)
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
M.setqflist = void(function(target: integer|string, opts: M.QFListOpts)
  opts = opts or {}
  if opts.open == nil then
    opts.open = true
  end
  local qfopts = {
    items = buildqflist(target),
    title = 'Hunks'
  }
  scheduler()
  if opts.use_location_list then
    local nr = opts.nr or 0
    vim.fn.setloclist(nr, {}, ' ', qfopts)
    if opts.open then
      if config.trouble then
        require'trouble'.open("loclist")
      else
        vim.cmd[[lopen]]
      end
    end
  else
    vim.fn.setqflist({}, ' ', qfopts)
    if opts.open then
      if config.trouble then
        require'trouble'.open("quickfix")
      else
        vim.cmd[[copen]]
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
M.setloclist = function(nr: integer, target: integer|string)
  M.setqflist(target, {
    nr = nr,
    use_location_list = true
  })
end

--- Get all the available line specific actions for the current
--- buffer at the cursor position.
---
--- Return: ~
---     Dictionary of action name to function which when called
---     performs action.
M.get_actions = function(): {string:function}
  local bufnr = current_buf()
  local bcache = cache[bufnr]
  if not bcache then
    return
  end
  local hunk = get_cursor_hunk(bufnr, bcache.hunks)

  local actions_l: {string} = {}

  local function add_action(action: string)
    actions_l[#actions_l+1] = action
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

  local actions: {string:function} = {}
  for _, a in ipairs(actions_l) do
    actions[a] = (M as {string:function})[a]
  end

  return actions
end

--- Refresh all buffers.
---
--- Attributes: ~
---     {async}
M.refresh = void(function()
  manager.setup_signs_and_highlights(true)
  require('gitsigns.current_line_blame').setup()
  for k, v in pairs(cache as {integer:CacheEntry}) do
    -- Invalidate cache fields
    v.compare_text = nil
    v.hunks = nil
    manager.update(k, v)
  end
end)

return M
