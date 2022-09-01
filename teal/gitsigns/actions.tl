local void      = require('gitsigns.async').void
local scheduler = require('gitsigns.async').scheduler

local config        = require('gitsigns.config').config
local mk_repeatable = require('gitsigns.repeat').mk_repeatable
local popup         = require('gitsigns.popup')
local util          = require('gitsigns.util')
local manager       = require('gitsigns.manager')
local git           = require('gitsigns.git')
local run_diff      = require('gitsigns.diff')

local gs_cache       = require('gitsigns.cache')
local cache          = gs_cache.cache
local CacheEntry     = gs_cache.CacheEntry

local gs_hunks    = require('gitsigns.hunks')
local Hunk        = gs_hunks.Hunk
local Hunk_Public = gs_hunks.Hunk_Public

local api = vim.api
local current_buf = api.nvim_get_current_buf

local record DiffthisOpts
  vertical: boolean
  split: string
end

local record NavHunkOpts
  forwards: boolean
  wrap: boolean
  navigation_message: boolean
  foldopen: boolean
  preview: boolean
end

local record BlameOpts
  full: boolean
  ignore_whitespace: boolean
end

local record M
  stage_hunk         : function({integer, integer})
  undo_stage_hunk    : function()
  reset_hunk         : function({integer, integer})

  stage_buffer       : function()
  reset_buffer       : function()
  reset_buffer_index : function()

  next_hunk          : function(NavHunkOpts)
  prev_hunk          : function(NavHunkOpts)
  preview_hunk       : function()
  select_hunk        : function()
  get_hunks          : function(bufnr: integer): {Hunk_Public}

  blame_line         : function(BlameOpts)
  change_base        : function(base: string, global: boolean)
  reset_base         : function(global: boolean)
  diffthis           : function(base: string, opts: DiffthisOpts)
  show               : function(base: string)

  test: function(base: string, opts: {string:any})

  record QFListOpts
    use_location_list: boolean
    nr: integer
    open: boolean
  end

  setqflist          : function(target:integer|string, opts: QFListOpts, callback: function)
  setloclist         : function(nr: integer, target:integer|string)

  get_actions        : function(bufnr: integer, lnum: integer)

  refresh            : function()
  toggle_signs       : function(boolean): boolean
  toggle_numhl       : function(boolean): boolean
  toggle_linehl      : function(boolean): boolean
  toggle_word_diff   : function(boolean): boolean
  toggle_current_line_blame : function(boolean): boolean
  toggle_deleted     : function(boolean): boolean

  arg_spec: {string:{integer,boolean,boolean}}
end

local type CmdFunc = function(pos_args: {any}, named_args: {string:any}, params: api.UserCmdParams)

-- Variations of functions from M which are used for the Gitsigns command
local C: {string:CmdFunc} = {}

--- Toggle |gitsigns-config-signbooleancolumn|
---
--- Parameters:~
---     {value} boolean|nil Value to set toggle. If `nil`
---     the toggle value is inverted.
---
--- Returns:~
---     Current value of |gitsigns-config-signcolumn|
M.toggle_signs = function(value: boolean): boolean
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
M.toggle_numhl = function(value: boolean): boolean
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
M.toggle_linehl = function(value: boolean): boolean
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
M.toggle_word_diff = function(value: boolean): boolean
  if value ~= nil then
    config.word_diff = value
  else
    config.word_diff = not config.word_diff
  end
  M.refresh()
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
M.toggle_current_line_blame = function(value: boolean): boolean
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
M.toggle_deleted = function(value: boolean): boolean
  if value ~= nil then
    config.show_deleted = value
  else
    config.show_deleted = not config.show_deleted
  end
  M.refresh()
  return config.show_deleted
end

local function get_cursor_hunk(bufnr: integer, hunks: {Hunk}): Hunk, integer
  bufnr = bufnr or current_buf()
  hunks = hunks or cache[bufnr].hunks

  local lnum = api.nvim_win_get_cursor(0)[1]
  return gs_hunks.find_hunk(lnum, hunks)
end

local function update(bufnr: integer)
  manager.update(bufnr)
  scheduler()
  if vim.wo.diff then
    require('gitsigns.diffthis').update(bufnr)
  end
end

local function get_range(params: api.UserCmdParams): {integer, integer}
  local range: {integer, integer}
  if params.range > 0 then
    range = {params.line1, params.line2}
  end
  return range
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
---     If running via command line, then this is taken from the
---     command modifiers.
M.stage_hunk = mk_repeatable(void(function(range: {integer, integer})
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

  bcache:invalidate()
  update(bufnr)
end))

C.stage_hunk = function(_pos_args: {any}, _named_args: {string:any}, params: api.UserCmdParams)
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
---     up the line range from which you want to reset the hunks.
M.reset_hunk = mk_repeatable(function(range: {integer, integer})
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
    lstart = hunk.added.start
    lend = hunk.added.start
  else
    lstart = hunk.added.start - 1
    lend = hunk.added.start - 1 + hunk.added.count
  end
  util.set_lines(bufnr, lstart, lend, hunk.removed.lines)
end)

C.reset_hunk = function(_pos_args: {any}, _named_args: {string:any}, params: api.UserCmdParams)
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
    print("No hunks to undo")
    return
  end

  bcache.git_obj:stage_hunks({hunk}, true)
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
  -- using git apply line by line instead of reseting whole file
  bcache.staged_diffs = {}

  bcache.git_obj:unstage_file()

  bcache:invalidate()
  update(bufnr)
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

-- Defer function to the next main event
local function defer(fn: function)
  if vim.in_fast_event() then
    vim.schedule(fn)
  else
    vim.defer_fn(fn, 1)
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

  local row = opts.forwards and hunk.added.start or hunk.vend
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
    if opts.preview or popup.is_open() then
      -- Use defer so the cursor change can settle, otherwise the popup might
      -- appear in the old position
      defer(M.preview_hunk)
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
---             • {preview}: (boolean)
---               Automatically open preview_hunk() upon navigating
---               to a hunk.
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

local HlMark = popup.HlMark

local function lines_format(fmt: {{{string,string|{HlMark}}}},
                            info: util.FmtInfo): {{{string,string|{HlMark}}}}

  local ret = vim.deepcopy(fmt)

  for _, line in ipairs(ret) do
    for _, s in ipairs(line) do
      s[1] = util.expand_format(s[1], info)
    end
  end

  return ret
end

local function hlmarks_for_hunk(hunk: Hunk, hl: string): {HlMark}
  local hls: {HlMark} = {}

  local removed, added = hunk.removed, hunk.added

  if hl then
    hls[#hls+1] = {
      hl_group  = hl,
      start_row = 0,
      end_row   = removed.count + added.count,
    }
  end

  hls[#hls+1] = {
    hl_group  = 'GitSignsDeletePreview',
    start_row = 0,
    end_row   = removed.count,
  }

  hls[#hls+1] = {
    hl_group  = 'GitSignsAddPreview',
    start_row = removed.count,
    end_row   = removed.count + added.count,
  }

  if config.diff_opts.internal then
    local removed_regions, added_regions =
      require('gitsigns.diff_int').run_word_diff(removed.lines, added.lines)
    for _, region in ipairs(removed_regions) do
      hls[#hls+1] = {
        hl_group  = 'GitSignsDeleteInline',
        start_row = region[1] - 1,
        start_col = region[3],
        end_col   = region[4],
      }
    end
    for _, region in ipairs(added_regions) do
      hls[#hls+1] = {
        hl_group  = 'GitSignsAddInline',
        start_row = region[1] - 1,
        start_col = region[3],
        end_col   = region[4],
      }
    end
  end

  return hls
end

local function insert_hunk_hlmarks(fmt: popup.LinesSpec, hunk: Hunk)
  for _, line in ipairs(fmt) do
    for _, s in ipairs(line) do
      local hl = s[2]
      if s[1] == '<hunk>' and hl is string then
        s[2] = hlmarks_for_hunk(hunk, hl)
      end
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

--- Preview the hunk at the cursor position in a floating
--- window.
M.preview_hunk = noautocmd(function()
  -- Wrap in noautocmd so vim-repeat continues to work
  local bufnr = current_buf()
  local bcache = cache[bufnr]
  if not bcache then
    return
  end

  local hunk, index = get_cursor_hunk(bufnr, bcache.hunks)

  if not hunk then return end

  local lines_fmt = {
    {{'Hunk <hunk_no> of <num_hunks>', 'Title'}},
    {{'<hunk>', 'NormalFloat' }}
  }

  insert_hunk_hlmarks(lines_fmt, hunk)

  local lines_spec = lines_format(lines_fmt, {
    hunk_no = index,
    num_hunks = #bcache.hunks,
    hunk = gs_hunks.patch_lines(hunk, vim.bo[bufnr].fileformat),
  })

  popup.create(lines_spec, config.preview_config)
end)

--- Select the hunk under the cursor.
M.select_hunk = function()
  local hunk = get_cursor_hunk()
  if not hunk then return end

  vim.cmd('normal! '..hunk.added.start..'GV'..hunk.vend..'G')
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
  bufnr = bufnr or current_buf()
  if not cache[bufnr] then return end
  local ret = {}
  for _, h in ipairs(cache[bufnr].hunks or {}) do
    ret[#ret+1] = {
      head    = h.head,
      lines   = gs_hunks.patch_lines(h, vim.bo[bufnr].fileformat),
      type    = h.type,
      added   = h.added,
      removed = h.removed
    }
  end
  return ret
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

local function create_blame_fmt(is_committed: boolean, full: boolean): popup.LinesSpec
  if not is_committed then
    return {
      {{'<author>', 'Label'}},
    }
  end

  local header = {
    {'<abbrev_sha> ', 'Directory'},
    {'<author> ', 'MoreMsg'},
    {'(<author_time:%Y-%m-%d %H:%M>)', 'Label'},
    {':', 'NormalFloat'}
  }

  if full then
    return {
      header,
      {{'<body>', 'NormalFloat'}},
      {{'Hunk <hunk_no> of <num_hunks>', 'Title'}, {' <hunk_head>', 'LineNr'}},
      {{'<hunk>', 'NormalFloat'}}
    }
  end

  return {
    header,
    {{'<summary>', 'NormalFloat'}}
  }
end

--- Run git blame on the current line and show the results in a
--- floating window.
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
M.blame_line = void(function(opts: BlameOpts)
  opts = opts or {}

  local bufnr = current_buf()
  local bcache = cache[bufnr]
  if not bcache then return end

  local loading = vim.defer_fn(function()
    popup.create({{{'Loading...', 'Title'}}}, config.preview_config)
  end, 1000)

  scheduler()
  local buftext = util.buf_lines(bufnr)
  local fileformat = vim.bo[bufnr].fileformat
  local lnum = api.nvim_win_get_cursor(0)[1]
  local result = bcache.git_obj:run_blame(buftext, lnum, opts.ignore_whitespace)
  pcall(function()
    loading:close()
  end)

  local is_committed = result.sha and tonumber('0x'..result.sha) ~= 0

  local blame_fmt = create_blame_fmt(is_committed, opts.full)

  local info = result as util.FmtInfo

  if is_committed and opts.full then
    info.body = bcache.git_obj:command{ 'show', '-s', '--format=%B', result.sha } as string

    local hunk: Hunk

    hunk, info.hunk_no, info.num_hunks = get_blame_hunk(bcache.git_obj.repo, result)

    info.hunk = gs_hunks.patch_lines(hunk, fileformat)
    info.hunk_head = hunk.head
    insert_hunk_hlmarks(blame_fmt, hunk)
  end

  scheduler()

  popup.create(lines_format(blame_fmt, info), config.preview_config)
end)

local function update_buf_base(buf: integer, bcache: CacheEntry, base: string)
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
M.change_base = void(function(base: string, global: boolean)
  base = util.calc_base(base)

  if global then
    config.base = base

    for bufnr, bcache in pairs(cache as {integer:CacheEntry}) do
      update_buf_base(bufnr, bcache, base)
    end
  else
    local bufnr = current_buf()
    local bcache = cache[bufnr]
    if not bcache then return end

    update_buf_base(bufnr, bcache, base)
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
M.diffthis = function(base: string, opts: DiffthisOpts)
  opts = opts or {}
  local diffthis = require('gitsigns.diffthis')
  if not opts.vertical then
    opts.vertical = config.diff_opts.vertical
  end
  diffthis.diffthis(base, opts as diffthis.DiffthisOpts)
end

C.diffthis = function(pos_args: {any}, named_args: {string:any}, params: api.UserCmdParams)
  local opts: DiffthisOpts = {
    vertical = named_args.vertical as boolean,
    split    = named_args.split as string
  }

  if params.smods then
    if params.smods.split ~= '' and opts.split == nil then
      opts.split = params.smods.split
    end
    if opts.vertical == nil then
      opts.vertical = params.smods.vertical
    end
  end

  M.diffthis(pos_args[1] as string, opts)
end

-- C.test = function(pos_args: {any}, named_args: {string:any}, params: api.UserCmdParams)
--   print('POS ARGS:', vim.inspect(pos_args))
--   print('NAMED ARGS:', vim.inspect(named_args))
--   print('PARAMS:', vim.inspect(params))
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
M.show = function(revision: string)
  local diffthis = require('gitsigns.diffthis')
  diffthis.show(revision)
end

local function hunks_to_qflist(buf_or_filename: number|string, hunks: {Hunk}, qflist: {vim.fn.QFItem})
  for i, hunk in ipairs(hunks) do
    qflist[#qflist+1] = {
      bufnr    = buf_or_filename is number and (buf_or_filename as integer) or nil,
      filename = buf_or_filename is string and buf_or_filename or nil,
      lnum = hunk.added.start,
      text = string.format('Lines %d-%d (%d/%d)',
      hunk.added.start, hunk.vend, i, #hunks),
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

    local repo = git.Repo.new(vim.loop.cwd())
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
  manager.reset_signs()
  require('gitsigns.highlight').setup_highlights()
  require('gitsigns.current_line_blame').setup()
  for k, v in pairs(cache as {integer:CacheEntry}) do
    v:invalidate()
    manager.update(k, v)
  end
end)

function M.get_cmd_func(name: string): CmdFunc
  return C[name]
end

return M
