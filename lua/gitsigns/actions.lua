local async = require('gitsigns.async')
local Hunks = require('gitsigns.hunks')
local manager = require('gitsigns.manager')
local message = require('gitsigns.message')
local util = require('gitsigns.util')

local config = require('gitsigns.config').config
local mk_repeatable = require('gitsigns.repeat').mk_repeatable
local cache = require('gitsigns.cache').cache

local api = vim.api
local current_buf = api.nvim_get_current_buf

local tointeger = util.tointeger

--- @class gitsigns.actions
local M = {}

--- @class Gitsigns.CmdParams.Smods
--- @field vertical boolean
--- @field split 'aboveleft'|'belowright'|'topleft'|'botright'

--- @class Gitsigns.CmdArgs
--- @field vertical? boolean
--- @field split? boolean
--- @field global? boolean
--- @field [integer] any

--- @class Gitsigns.CmdParams
--- @field range integer
--- @field line1 integer
--- @field line2 integer
--- @field count integer
--- @field smods Gitsigns.CmdParams.Smods

--- Variations of functions from M which are used for the Gitsigns command
--- @type table<string,fun(args: Gitsigns.CmdArgs, params: Gitsigns.CmdParams)>
local C = {}

local CP = {}

--- @param arglead string
--- @return string[]
local function complete_heads(arglead)
  --- @type string[]
  local all =
    vim.fn.systemlist({ 'git', 'rev-parse', '--symbolic', '--branches', '--tags', '--remotes' })
  return vim.tbl_filter(
    --- @param x string
    --- @return boolean
    function(x)
      return vim.startswith(x, arglead)
    end,
    all
  )
end

--- Detach Gitsigns from all buffers it is attached to.
function M.detach_all()
  require('gitsigns.attach').detach_all()
end

--- Detach Gitsigns from the buffer {bufnr}. If {bufnr} is not
--- provided then the current buffer is used.
---
--- @param bufnr integer Buffer number
function M.detach(bufnr)
  require('gitsigns.attach').detach(bufnr)
end

--- Attach Gitsigns to the buffer.
---
--- Attributes: ~
---     {async}
---
--- @param bufnr integer Buffer number
--- @param ctx Gitsigns.GitContext|nil
---     Git context data that may optionally be used to attach to any
---     buffer that represents a real git object.
---     • {file}: (string)
---       Path to the file represented by the buffer, relative to the
---       top-level.
---     • {toplevel}: (string?)
---       Path to the top-level of the parent git repository.
---     • {gitdir}: (string?)
---       Path to the git directory of the parent git repository
---       (typically the ".git/" directory).
---     • {commit}: (string?)
---       The git revision that the file belongs to.
---     • {base}: (string?)
---       The git revision that the file should be compared to.
--- @param _trigger? string
M.attach = async.create(3, function(bufnr, ctx, _trigger)
  require('gitsigns.attach').attach(bufnr or api.nvim_get_current_buf(), ctx, _trigger)
end)

--- Toggle |gitsigns-config-signbooleancolumn|
---
--- @param value boolean|nil Value to set toggle. If `nil`
---     the toggle value is inverted.
--- @return boolean : Current value of |gitsigns-config-signcolumn|
M.toggle_signs = function(value)
  if value ~= nil then
    config.signcolumn = value
  else
    config.signcolumn = not config.signcolumn
  end
  return config.signcolumn
end

--- Toggle |gitsigns-config-numhl|
---
--- @param value boolean|nil Value to set toggle. If `nil`
---     the toggle value is inverted.
---
--- @return boolean : Current value of |gitsigns-config-numhl|
M.toggle_numhl = function(value)
  if value ~= nil then
    config.numhl = value
  else
    config.numhl = not config.numhl
  end
  return config.numhl
end

--- Toggle |gitsigns-config-linehl|
---
--- @param value boolean|nil Value to set toggle. If `nil`
---     the toggle value is inverted.
--- @return boolean : Current value of |gitsigns-config-linehl|
M.toggle_linehl = function(value)
  if value ~= nil then
    config.linehl = value
  else
    config.linehl = not config.linehl
  end
  return config.linehl
end

--- Toggle |gitsigns-config-word_diff|
---
--- @param value boolean|nil Value to set toggle. If `nil`
---     the toggle value is inverted.
--- @return boolean : Current value of |gitsigns-config-word_diff|
M.toggle_word_diff = function(value)
  if value ~= nil then
    config.word_diff = value
  else
    config.word_diff = not config.word_diff
  end
  -- Don't use refresh() to avoid flicker
  util.redraw({ buf = 0, range = { vim.fn.line('w0') - 1, vim.fn.line('w$') } })
  return config.word_diff
end

--- Toggle |gitsigns-config-current_line_blame|
---
--- @param value boolean|nil Value to set toggle. If `nil`
---     the toggle value is inverted.
--- @return boolean : Current value of |gitsigns-config-current_line_blame|
M.toggle_current_line_blame = function(value)
  if value ~= nil then
    config.current_line_blame = value
  else
    config.current_line_blame = not config.current_line_blame
  end
  return config.current_line_blame
end

--- @deprecated Use |gitsigns.preview_hunk_inline()|
--- Toggle |gitsigns-config-show_deleted|
---
--- @param value boolean|nil Value to set toggle. If `nil`
---     the toggle value is inverted.
--- @return boolean : Current value of |gitsigns-config-show_deleted|
M.toggle_deleted = function(value)
  if value ~= nil then
    config.show_deleted = value
  else
    config.show_deleted = not config.show_deleted
  end
  return config.show_deleted
end

--- @async
--- @param bufnr integer
local function update(bufnr)
  local bcache = cache[bufnr]
  if not bcache then
    return
  end

  manager.update(bufnr)
  if not bcache:schedule() then
    return
  end
  if vim.wo.diff then
    require('gitsigns.actions.diffthis').update(bufnr)
  end
end

--- @param params Gitsigns.CmdParams
--- @return [integer,integer]? range Range of lines to operate on.
local function get_range(params)
  local range --- @type [integer, integer]?
  if params.range > 0 then
    range = { params.line1, params.line2 }
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
--- @param range table|nil List-like table of two integers making
---             up the line range from which you want to stage the hunks.
---             If running via command line, then this is taken from the
---             command modifiers.
--- @param opts table|nil Additional options:
---             • {greedy}: (boolean)
---               Stage all contiguous hunks. Only useful if 'diff_opts'
---               contains `linematch`. Defaults to `true`.
M.stage_hunk = mk_repeatable(async.create(2, function(range, opts)
  --- @cast range [integer, integer]?

  opts = opts or {}
  local bufnr = current_buf()
  local bcache = cache[bufnr]
  if not bcache then
    return
  end

  if not util.Path.exists(bcache.file) then
    print('Error: Cannot stage lines. Please add the file to the working tree.')
    return
  end

  bcache.git_obj:lock(function()
    local hunk = bcache:get_hunk(range, opts.greedy ~= false, false)

    local invert = false
    if not hunk then
      invert = true
      hunk = bcache:get_hunk(range, opts.greedy ~= false, true)
    end

    if not hunk then
      api.nvim_echo({ { 'No hunk to stage', 'WarningMsg' } }, false, {})
      return
    end

    local err = bcache.git_obj:stage_hunks({ hunk }, invert)
    if err then
      message.error(err)
      return
    end
    table.insert(bcache.staged_diffs, hunk)
  end)

  bcache:invalidate(true)
  update(bufnr)
end))

C.stage_hunk = function(_, params)
  M.stage_hunk(get_range(params))
end

--- @param bufnr integer
--- @param hunk Gitsigns.Hunk.Hunk
local function reset_hunk(bufnr, hunk)
  local lstart, lend --- @type integer, integer
  if hunk.type == 'delete' then
    lstart = hunk.added.start
    lend = hunk.added.start
  else
    lstart = hunk.added.start - 1
    lend = hunk.added.start - 1 + hunk.added.count
  end

  if hunk.removed.no_nl_at_eof ~= hunk.added.no_nl_at_eof then
    local no_eol = hunk.added.no_nl_at_eof or false
    vim.bo[bufnr].endofline = no_eol
    vim.bo[bufnr].fixendofline = no_eol
  end

  util.set_lines(bufnr, lstart, lend, hunk.removed.lines)
end

--- Reset the lines of the hunk at the cursor position, or all
--- lines in the given range. If {range} is provided, all lines in
--- the given range are reset. This supports partial-hunks,
--- meaning if a range only includes a portion of a particular
--- hunk, only the lines within the range will be reset.
---
--- @param range table|nil List-like table of two integers making
---     up the line range from which you want to reset the hunks.
---     If running via command line, then this is taken from the
---     command modifiers.
--- @param opts table|nil Additional options:
---     • {greedy}: (boolean)
---       Stage all contiguous hunks. Only useful if 'diff_opts'
---       contains `linematch`. Defaults to `true`.
M.reset_hunk = mk_repeatable(async.create(2, function(range, opts)
  --- @cast range [integer, integer]?

  opts = opts or {}
  local bufnr = current_buf()
  local bcache = cache[bufnr]
  if not bcache then
    return
  end

  local hunk = bcache:get_hunk(range, opts.greedy ~= false, false)

  if not hunk then
    api.nvim_echo({ { 'No hunk to reset', 'WarningMsg' } }, false, {})
    return
  end

  reset_hunk(bufnr, hunk)
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

  local hunks = bcache.hunks
  if not hunks or #hunks == 0 then
    api.nvim_echo({ { 'No unstaged changes in the buffer to reset', 'WarningMsg' } }, false, {})
    return
  end

  for i = #hunks, 1, -1 do
    reset_hunk(bufnr, hunks[i] --[[@as Gitsigns.Hunk.Hunk]])
  end
end

--- @deprecated use |gitsigns.stage_hunk()| on staged signs
--- Undo the last call of stage_hunk().
---
--- Note: only the calls to stage_hunk() performed in the current
--- session can be undone.
---
--- Attributes: ~
---     {async}
M.undo_stage_hunk = async.create(0, function()
  local bufnr = current_buf()
  local bcache = cache[bufnr]
  if not bcache then
    return
  end

  bcache.git_obj:lock(function()
    local hunk = table.remove(bcache.staged_diffs)
    if not hunk then
      print('No hunks to undo')
      return
    end

    local err = bcache.git_obj:stage_hunks({ hunk }, true)
    if err then
      message.error(err)
      return
    end
  end)

  bcache:invalidate(true)
  update(bufnr)
end)

--- Stage all hunks in current buffer.
---
--- Attributes: ~
---     {async}
M.stage_buffer = async.create(0, function()
  local bufnr = current_buf()
  local bcache = cache[bufnr]
  if not bcache then
    return
  end

  bcache.git_obj:lock(function()
    -- Only process files with existing hunks
    local hunks = bcache.hunks
    if not hunks or #hunks == 0 then
      print('No unstaged changes in file to stage')
      return
    end

    if not util.Path.exists(bcache.git_obj.file) then
      print('Error: Cannot stage file. Please add it to the working tree.')
      return
    end

    local err = bcache.git_obj:stage_hunks(hunks)
    if err then
      message.error(err)
      return
    end

    for _, hunk in ipairs(hunks) do
      table.insert(bcache.staged_diffs, hunk)
    end
  end)

  bcache:invalidate(true)
  update(bufnr)
end)

--- Unstage all hunks for current buffer in the index. Note:
--- Unlike |gitsigns.undo_stage_hunk()| this doesn't simply undo
--- stages, this runs an `git reset` on current buffers file.
---
--- Attributes: ~
---     {async}
M.reset_buffer_index = async.create(0, function()
  local bufnr = current_buf()
  local bcache = cache[bufnr]
  if not bcache then
    return
  end

  bcache.git_obj:lock(function()
    -- `bcache.staged_diffs` won't contain staged changes outside of current
    -- neovim session so signs added from this unstage won't be complete They will
    -- however be fixed by gitdir watcher and properly updated We should implement
    -- some sort of initial population from git diff, after that this function can
    -- be improved to check if any staged hunks exists and it can undo changes
    -- using git apply line by line instead of resetting whole file
    bcache.staged_diffs = {}

    bcache.git_obj:unstage_file()
  end)

  bcache:invalidate(true)
  update(bufnr)
end)

--- Jump to hunk in the current buffer. If a hunk preview
--- (popup or inline) was previously opened, it will be re-opened
--- at the next hunk.
---
--- Attributes: ~
---     {async}
---
--- @param direction 'first'|'last'|'next'|'prev'
--- @param opts table|nil Configuration table. Keys:
---     • {wrap}: (boolean)
---       Whether to loop around file or not. Defaults
---       to the value 'wrapscan'
---     • {navigation_message}: (boolean)
---       Whether to show navigation messages or not.
---       Looks at 'shortmess' for default behaviour.
---     • {foldopen}: (boolean)
---       Expand folds when navigating to a hunk which is
---       inside a fold. Defaults to `true` if 'foldopen'
---       contains `search`.
---     • {preview}: (boolean)
---       Automatically open preview_hunk() upon navigating
---       to a hunk.
---     • {greedy}: (boolean)
---       Only navigate between non-contiguous hunks. Only useful if
---       'diff_opts' contains `linematch`. Defaults to `true`.
---     • {target}: (`'unstaged'|'staged'|'all'`)
---       Which kinds of hunks to target. Defaults to `'unstaged'`.
---     • {count}: (integer)
---       Number of times to advance. Defaults to |v:count1|.
M.nav_hunk = async.create(2, function(direction, opts)
  --- @cast opts Gitsigns.NavOpts?
  require('gitsigns.actions.nav').nav_hunk(direction, opts)
end)

C.nav_hunk = function(args, _)
  M.nav_hunk(args[1], args)
end

--- @deprecated use |gitsigns.nav_hunk()|
--- Jump to the next hunk in the current buffer. If a hunk preview
--- (popup or inline) was previously opened, it will be re-opened
--- at the next hunk.
---
--- Attributes: ~
---     {async}
---
--- Parameters: ~
---     See |gitsigns.nav_hunk()|.
M.next_hunk = async.create(1, function(opts)
  require('gitsigns.actions.nav').nav_hunk('next', opts)
end)

C.next_hunk = function(args, _)
  M.nav_hunk('next', args)
end

--- @deprecated use |gitsigns.nav_hunk()|
--- Jump to the previous hunk in the current buffer. If a hunk preview
--- (popup or inline) was previously opened, it will be re-opened
--- at the previous hunk.
---
--- Attributes: ~
---     {async}
---
--- Parameters: ~
---     See |gitsigns.nav_hunk()|.
M.prev_hunk = async.create(1, function(opts)
  require('gitsigns.actions.nav').nav_hunk('prev', opts)
end)

C.prev_hunk = function(args, _)
  M.nav_hunk('prev', args)
end

--- Preview the hunk at the cursor position in a floating
--- window. If the preview is already open, calling this
--- will cause the window to get focus.
M.preview_hunk = function()
  require('gitsigns.actions.preview').preview_hunk()
end

--- Preview the hunk at the cursor position inline in the buffer.
M.preview_hunk_inline = async.create(0, function()
  require('gitsigns.actions.preview').preview_hunk_inline()
end)

--- Select the hunk under the cursor.
---
--- @param opts table|nil Additional options:
---             • {greedy}: (boolean)
---               Select all contiguous hunks. Only useful if 'diff_opts'
---               contains `linematch`. Defaults to `true`.
M.select_hunk = function(opts)
  local bufnr = current_buf()
  local bcache = cache[bufnr]
  if not bcache then
    return
  end

  opts = opts or {}

  local hunk --- @type Gitsigns.Hunk.Hunk?
  async
    .run(function()
      hunk = bcache:get_hunk(nil, opts.greedy ~= false)
    end)
    :wait()

  if not hunk then
    return
  end

  if vim.fn.mode():find('v') ~= nil then
    vim.cmd('normal! ' .. hunk.added.start .. 'GoV' .. hunk.vend .. 'G')
  else
    vim.cmd('normal! ' .. hunk.added.start .. 'GV' .. hunk.vend .. 'G')
  end
end

--- Get hunk array for specified buffer.
---
--- @param bufnr integer Buffer number, if not provided (or 0)
---             will use current buffer.
--- @return table|nil : Array of hunk objects.
---     Each hunk object has keys:
---         • `"type"`: String with possible values: "add", "change",
---           "delete"
---         • `"head"`: Header that appears in the unified diff
---           output.
---         • `"lines"`: Line contents of the hunks prefixed with
---           either `"-"` or `"+"`.
---         • `"removed"`: Sub-table with fields:
---           • `"start"`: Line number (1-based)
---           • `"count"`: Line count
---         • `"added"`: Sub-table with fields:
---           • `"start"`: Line number (1-based)
---           • `"count"`: Line count
M.get_hunks = function(bufnr)
  bufnr = bufnr or current_buf()
  if not cache[bufnr] then
    return
  end
  local ret = {} --- @type Gitsigns.Hunk.Hunk_Public[]
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

--- Run git blame on the current line and show the results in a
--- floating window. If already open, calling this will cause the
--- window to get focus.
---
--- Attributes: ~
---     {async}
---
--- @param opts table|nil Additional options:
---     • {full}: (boolean)
---       Display full commit message with hunk.
---     • {ignore_whitespace}: (boolean)
---       Ignore whitespace when running blame.
---     • {extra_opts}: (string[])
---       Extra options passed to `git-blame`.
M.blame_line = async.create(1, function(opts)
  --- @cast opts Gitsigns.LineBlameOpts?
  require('gitsigns.actions.blame_line')(opts)
end)

C.blame_line = function(args, _)
  M.blame_line(args)
end

--- Run git-blame on the current file and open the results
--- in a scroll-bound vertical split.
---
--- Mappings:
---   <CR> is mapped to open a menu with the other mappings
---        Note: <Alt> must be held to activate the mappings whilst the menu is
---        open.
---   s   [Show commit] in a vertical split.
---   S   [Show commit] in a new tab.
---   r   [Reblame at commit]
---
--- Attributes: ~
---     {async}
M.blame = async.create(0, function()
  require('gitsigns.actions.blame').blame()
end)

--- @async
--- @param bcache Gitsigns.CacheEntry
--- @param base string?
local function update_buf_base(bcache, base)
  bcache.file_mode = base == 'FILE'
  if not bcache.file_mode then
    bcache.git_obj:change_revision(base)
  end
  bcache:invalidate(true)
  update(bcache.bufnr)
end

--- Change the base revision to diff against. If {base} is not
--- given, then the original base is used. If {global} is given
--- and true, then change the base revision of all buffers,
--- including any new buffers.
---
--- Attributes: ~
---     {async}
---
--- Examples: >lua
---   -- Change base to 1 commit behind head
---   require('gitsigns').change_base('HEAD~1')
---   -- :Gitsigns change_base HEAD~1
---
---   -- Also works using the Gitsigns command
---   :Gitsigns change_base HEAD~1
---
---   -- Other variations
---   require('gitsigns').change_base('~1')
---   -- :Gitsigns change_base ~1
---   require('gitsigns').change_base('~')
---   -- :Gitsigns change_base ~
---   require('gitsigns').change_base('^')
---   -- :Gitsigns change_base ^
---
---   -- Commits work too
---   require('gitsigns').change_base('92eb3dd')
---   -- :Gitsigns change_base 92eb3dd
---
---   -- Revert to original base
---   require('gitsigns').change_base()
---   -- :Gitsigns change_base
--- <
---
--- For a more complete list of ways to specify bases, see
--- |gitsigns-revision|.
---
--- @param base string|nil The object/revision to diff against.
--- @param global boolean|nil Change the base of all buffers.
M.change_base = async.create(2, function(base, global)
  base = util.norm_base(base)

  if global then
    config.base = base

    for _, bcache in pairs(cache) do
      update_buf_base(bcache, base)
    end
  else
    local bufnr = current_buf()
    local bcache = cache[bufnr]
    if not bcache then
      return
    end

    update_buf_base(bcache, base)
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
--- Examples: >lua
---   -- Diff against the index
---   require('gitsigns').diffthis()
---   -- :Gitsigns diffthis
---
---   -- Diff against the last commit
---   require('gitsigns').diffthis('~1')
---   -- :Gitsigns diffthis ~1
--- <
---
--- For a more complete list of ways to specify bases, see
--- |gitsigns-revision|.
---
--- Attributes: ~
---     {async}
---
--- @param base string|nil Revision to diff against. Defaults to index.
--- @param opts table|nil Additional options:
---     • {vertical}: {boolean}. Split window vertically. Defaults to
---       config.diff_opts.vertical. If running via command line, then
---       this is taken from the command modifiers.
---     • {split}: {string}. One of: 'aboveleft', 'belowright',
---       'botright', 'rightbelow', 'leftabove', 'topleft'. Defaults to
---       'aboveleft'. If running via command line, then this is taken
---       from the command modifiers.
M.diffthis = async.create(2, function(base, opts)
  --- @cast opts Gitsigns.DiffthisOpts
  -- TODO(lewis6991): can't pass numbers as strings from the command line
  if base ~= nil then
    base = tostring(base)
  end
  opts = opts or {}
  if opts.vertical == nil then
    opts.vertical = config.diff_opts.vertical
  end
  require('gitsigns.actions.diffthis').diffthis(base, opts)
end)

C.diffthis = function(args, params)
  -- TODO(lewis6991): validate these
  local opts = {
    vertical = config.diff_opts.vertical,
    split = args.split,
  }

  if args.vertical ~= nil then
    opts.vertical = args.vertical
  end

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
--- Examples: >lua
---   -- View the index version of the file
---   require('gitsigns').show()
---   -- :Gitsigns show
---
---   -- View revision of file in the last commit
---   require('gitsigns').show('~1')
---   -- :Gitsigns show ~1
--- <
---
--- For a more complete list of ways to specify bases, see
--- |gitsigns-revision|.
---
--- Attributes: ~
---     {async}
---
--- @param revision string?
M.show = async.create(1, function(revision, _callback)
  require('gitsigns.actions.diffthis').show(nil, revision)
end)

C.show = function(args, _)
  local revision = args[1]
  if revision ~= nil then
    revision = tostring(revision)
  end
  M.show(revision)
end

CP.show = complete_heads

--- Show revision {base} commit in split or tab
---
--- @param revision? string? (default: 'HEAD')
--- @param open? 'vsplit'|'tabnew'
M.show_commit = async.create(2, function(revision, open)
  require('gitsigns.actions.show_commit')(revision, open)
end)

C.show_commit = function(args, _)
  local revision, open = args[1], args[2]
  M.show_commit(revision, open)
end

CP.show_commit = complete_heads

--- Populate the quickfix list with hunks. Automatically opens the
--- quickfix window.
---
--- Attributes: ~
---     {async}
---
--- @param target integer|'attached'|'all'|nil
---     Specifies which files hunks are collected from.
---     Possible values.
---     • [integer]: The buffer with the matching buffer
---       number. `0` for current buffer (default).
---     • `"attached"`: All attached buffers.
---     • `"all"`: All modified files for each git
---       directory of all attached buffers in addition
---       to the current working directory.
--- @param opts table|nil Additional options:
---     • {use_location_list}: (boolean)
---       Populate the location list instead of the
---       quickfix list. Default to `false`.
---     • {nr}: (integer)
---       Window number or ID when using location list.
---       Expand folds when navigating to a hunk which is
---       inside a fold. Defaults to `0`.
---     • {open}: (boolean)
---       Open the quickfix/location list viewer.
---       Defaults to `true`.
M.setqflist = async.create(2, function(target, opts)
  require('gitsigns.actions.qflist').setqflist(target, opts)
end)

C.setqflist = function(args, _)
  local target = tointeger(args[1]) or args[1]
  M.setqflist(target, args)
end

--- Populate the location list with hunks. Automatically opens the
--- location list window.
---
--- Alias for: `setqflist({target}, { use_location_list = true, nr = {nr} }`
---
--- Attributes: ~
---     {async}
---
--- @param nr? integer Window number or the |window-ID|.
---     `0` for the current window (default).
--- @param target integer|'attached'|'all'|nil See |gitsigns.setqflist()|.
M.setloclist = function(nr, target)
  M.setqflist(target, {
    nr = nr,
    use_location_list = true,
  })
end

C.setloclist = function(args, _)
  local target = tointeger(args[2]) or args[2]
  M.setloclist(tointeger(args[1]), target)
end

--- Get all the available line specific actions for the current
--- buffer at the cursor position.
---
--- @return table|nil : Dictionary of action name to function which when called
---     performs action.
M.get_actions = function()
  local bufnr = current_buf()
  local bcache = cache[bufnr]
  if not bcache then
    return
  end
  local hunk = bcache:get_cursor_hunk()

  --- @type string[]
  local actions_l = {}

  if hunk then
    vim.list_extend(actions_l, {
      'stage_hunk',
      'reset_hunk',
      'preview_hunk',
      'select_hunk',
    })
  else
    actions_l[#actions_l + 1] = 'blame_line'
  end

  if not vim.tbl_isempty(bcache.staged_diffs) then
    actions_l[#actions_l + 1] = 'undo_stage_hunk'
  end

  local actions = {} --- @type table<string,function>
  for _, a in ipairs(actions_l) do
    actions[a] = M[a] --[[@as function]]
  end

  return actions
end

for name, f in
  pairs(M --[[@as table<string,function>]])
do
  if vim.startswith(name, 'toggle') then
    C[name] = function(args)
      f(args[1])
    end
  end
end

--- Refresh all buffers.
---
--- Attributes: ~
---     {async}
M.refresh = async.create(0, function()
  manager.reset_signs()
  require('gitsigns.highlight').setup_highlights()
  require('gitsigns.current_line_blame').setup()
  for k, v in pairs(cache) do
    v:invalidate(true)
    manager.update(k)
  end
end)

--- @param name string
--- @return fun(args: table, params: Gitsigns.CmdParams)
function M._get_cmd_func(name)
  return C[name]
end

--- @param name string
--- @return (fun(arglead: string): string[])?
function M._get_cmp_func(name)
  return CP[name]
end

return M
