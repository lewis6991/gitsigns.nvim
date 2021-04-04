local a = require('plenary/async_lib/async')
local void  = a.void
local await = a.await
local async = a.async
local scheduler = a.scheduler

local function void_async(func: function): function
  return void(async(func))
end

local gs_debounce       = require('gitsigns/debounce')
local debounce_trailing = gs_debounce.debounce_trailing

local gs_popup          = require('gitsigns/popup')
local gs_hl             = require('gitsigns/highlight')

local signs             = require('gitsigns/signs')
local Sign              = signs.Sign

local gs_config         = require('gitsigns/config')
local Config            = gs_config.Config

local mk_repeatable     = require('gitsigns/repeat').mk_repeatable

local apply_mappings    = require('gitsigns/mappings')

local git               = require('gitsigns/git')
local util              = require('gitsigns/util')

local gs_hunks          = require("gitsigns/hunks")
local create_patch      = gs_hunks.create_patch
local process_hunks     = gs_hunks.process_hunks
local Hunk              = gs_hunks.Hunk

local diff              = require('gitsigns.diff')

local gs_debug          = require("gitsigns/debug")
local dprint            = gs_debug.dprint

local Status            = require("gitsigns/status")

local api = vim.api
local uv = vim.loop
local current_buf = api.nvim_get_current_buf

local M: {string:function} = {}

local config: Config

local namespace: integer

local record CacheEntry
  file          : string
  relpath       : string
  object_name   : string
  mode_bits     : string
  toplevel      : string
  gitdir        : string
  username      : string
  staged        : string
  staged_text   : {string}
  abbrev_head   : string
  has_conflicts : boolean
  hunks         : {Hunk}
  staged_diffs  : {Hunk}
  pending_signs : {integer:Sign}
  index_watcher : vim.loop.FSPollObj -- Timer object watching the files index
end

local cache: {integer:CacheEntry} = {}

local function get_cursor_hunk(bufnr: integer, hunks: {Hunk}): Hunk
  bufnr = bufnr or current_buf()
  hunks = hunks or cache[bufnr].hunks

  local lnum = api.nvim_win_get_cursor(0)[1]
  return gs_hunks.find_hunk(lnum, hunks)
end

local function apply_win_signs(bufnr: integer, pending: {integer:Sign}, top: integer, bot: integer)
  -- If called without top or bot, then assume this is the first call after
  -- clearing all the signs
  local first_apply = top == nil

  if config.use_decoration_api then
    -- Just apply to signs visible in window
    top = top or vim.fn.line('w0')
    bot = bot or vim.fn.line('w$')
  else
    top = top or 0
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

local update_cnt = 0

local update = async(function(bufnr: integer, bcache: CacheEntry)
  bcache = bcache or cache[bufnr]
  if not bcache then
    error('Cache for buffer '..bufnr..' was nil')
    return
  end

  await(scheduler())
  local buftext = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local stage = bcache.has_conflicts and 1 or 0

  if config.use_internal_diff then
    if not bcache.staged_text or config._refresh_staged_on_update then
      bcache.staged_text = await(git.get_staged_text(bcache.toplevel, bcache.relpath, stage))
    end
    bcache.hunks = diff.run_diff(bcache.staged_text, buftext, config.diff_algorithm)
  else
    await(git.get_staged(bcache.toplevel, bcache.relpath, stage, bcache.staged))
    bcache.hunks = await(git.run_diff(bcache.staged, buftext, config.diff_algorithm))
  end
  bcache.pending_signs = process_hunks(bcache.hunks)

  await(scheduler())

  -- Apply signs to the window. Other signs will be added by the decoration
  -- provider as they are drawn.
  apply_win_signs(bufnr, bcache.pending_signs)

  Status:update(bufnr, gs_hunks.get_summary(bcache.hunks, bcache.abbrev_head))

  update_cnt = update_cnt + 1
  dprint(string.format('updates: %s, jobs: %s', update_cnt, util.job_cnt), bufnr, 'update')
end)

-- Define in setup so it can be debounced on updatetime
local update_debounced: function(integer)

local watch_index = function(bufnr: integer, gitdir: string, on_change: function): uv.FSPollObj
  dprint('Watching index', bufnr, 'watch_index')
  local index = gitdir..util.path_sep..'index'
  local w = uv.new_fs_poll()
  w:start(index, config.watch_index.interval, on_change)
  return w
end

local stage_hunk = void_async(function()
  local bufnr = current_buf()
  local bcache = cache[bufnr]
  if not bcache then
    return
  end

  local hunk = get_cursor_hunk(bufnr, bcache.hunks)
  if not hunk then
    return
  end

  if not util.path_exists(bcache.file) then
    print("Error: Cannot stage lines. Please add the file to the working tree.")
    return
  end

  if not bcache.object_name or bcache.has_conflicts then
    if not bcache.object_name then
      -- If there is no object_name then it is not yet in the index so add it
      await(git.add_file(bcache.toplevel, bcache.relpath))
    else
      -- Update the index with the common ancestor (stage 1) which is what bcache
      -- stores
      await(git.update_index(bcache.toplevel, bcache.mode_bits, bcache.object_name, bcache.relpath))
    end

    -- Update the cache
    _, bcache.object_name, bcache.mode_bits, bcache.has_conflicts =
      await(git.file_info(bcache.relpath, bcache.toplevel))
  end

  local lines = create_patch(bcache.relpath, hunk, bcache.mode_bits)

  await(git.stage_lines(bcache.toplevel, lines))

  table.insert(bcache.staged_diffs, hunk)

  local hunk_signs = process_hunks({hunk})

  await(scheduler())

  -- If watch_index is enabled then that will eventually kick in and update the
  -- signs, however for  smoother UX we can update the signs immediately without
  -- running a full diff.
  --
  -- We cannot update the status bar as that requires a full diff.
  for lnum, _ in pairs(hunk_signs) do
    signs.remove(bufnr, lnum)
  end
end)

local function reset_hunk(bufnr: integer, hunk: Hunk)
  bufnr = bufnr or current_buf()
  hunk = hunk or get_cursor_hunk(bufnr)
  if not hunk then
    return
  end

  local lstart, lend: integer, integer
  if hunk.type == 'delete' then
    lstart = hunk.start
    lend = hunk.start
  else
    local length = vim.tbl_count(vim.tbl_filter(function(l: string): boolean
      return vim.startswith(l, '+')
    end, hunk.lines))

    lstart = hunk.start - 1
    lend = hunk.start - 1 + length
  end
  api.nvim_buf_set_lines(bufnr, lstart, lend, false, gs_hunks.extract_removed(hunk))
end

local function reset_buffer()
  local bufnr = current_buf()
  local bcache = cache[bufnr]
  if not bcache then
    return
  end

  for _, hunk in ipairs(bcache.hunks) do
    reset_hunk(bufnr, hunk)
  end
end

local undo_stage_hunk = void_async(function()
  local bufnr = current_buf()
  local bcache = cache[bufnr]
  if not bcache then
    return
  end

  local hunk = bcache.staged_diffs[#bcache.staged_diffs]

  if not hunk then
    print("No hunks to undo")
    return
  end

  local lines = create_patch(bcache.relpath, hunk, bcache.mode_bits, true)

  await(git.stage_lines(bcache.toplevel, lines))

  table.remove(bcache.staged_diffs)

  local hunk_signs = process_hunks({hunk})

  await(scheduler())
  signs.add(config, bufnr, hunk_signs)
end)

local record NavHunkOpts
  forwards: boolean
  wrap: boolean
end

local function nav_hunk(options: NavHunkOpts)
  local bcache = cache[current_buf()]
  if not bcache then
    return
  end
  local hunks = bcache.hunks
  if not hunks or vim.tbl_isempty(hunks) then
    return
  end
  local line = api.nvim_win_get_cursor(0)[1]
  -- wrap around
  local wrap = options.wrap ~= nil and options.wrap or vim.o.wrapscan
  local hunk = gs_hunks.find_nearest_hunk(line, hunks, options.forwards, wrap)
  local row = options.forwards and hunk.start or hunk.dend
  if row then
    -- Handle topdelete
    if row == 0 then
      row = 1
    end
    api.nvim_win_set_cursor(0, {row, 0})
  end
end

local function next_hunk(options: NavHunkOpts)
  options = options or {}
  options.forwards = true
  nav_hunk(options)
end

local function prev_hunk(options: NavHunkOpts)
  options = options or {}
  options.forwards = false
  nav_hunk(options)
end

-- When this is called interactively (with no arguments) we want to remove all
-- the signs, however if called via a detach event (due to nvim_buf_attach) then
-- we don't want to clear the signs in case the buffer is just being updated due
-- to the file externally changeing. When this happens a detach and attach event
-- happen in sequence and so we keep the old signs to stop the sign column width
-- moving about between updates.
local function detach(bufnr: integer, keep_signs: boolean)
  bufnr = bufnr or current_buf()
  dprint('Detached', bufnr)
  local bcache = cache[bufnr]
  if not bcache then
    dprint('Cache was nil', bufnr)
    return
  end

  if not keep_signs then
    -- Remove all the signs
    vim.fn.sign_unplace('gitsigns_ns', {buffer = bufnr})
  end

  -- Clear status variables
  Status:clear(bufnr)

  os.remove(bcache.staged)

  local w = bcache.index_watcher
  if w then
    w:stop()
  else
    dprint('Index_watcher was nil', bufnr)
  end

  cache[bufnr] = nil
end

local function detach_all()
  for k, _ in pairs(cache) do
    detach(k)
  end
end

local function apply_keymaps(bufonly: boolean)
  apply_mappings(config.keymaps as {string:any}, bufonly)
end

local function get_buf_path(bufnr: integer): string
  return
    uv.fs_realpath(api.nvim_buf_get_name(bufnr))
    or
    api.nvim_buf_call(bufnr, function(): string
      return vim.fn.expand('%:p')
    end)
end

local function index_update_handler(cbuf: integer): function
  return void_async(function(err: string)
    if err then
      dprint('Index update error: '..err, cbuf, 'watcher_cb')
      return
    end
    dprint('Index update', cbuf, 'watcher_cb')
    local bcache = cache[cbuf]

    _, _, bcache.abbrev_head = await(git.get_repo_info(bcache.toplevel))

    Status:update_head(cbuf, bcache.abbrev_head)

    local _, object_name0, mode_bits0, has_conflicts =
      await(git.file_info(bcache.file, bcache.toplevel))

    if object_name0 == bcache.object_name then
      dprint('File not changed', cbuf, 'watcher_cb')
      return
    end

    bcache.object_name   = object_name0
    bcache.mode_bits     = mode_bits0
    bcache.has_conflicts = has_conflicts
    bcache.staged_text   = nil -- Invalidate

    await(update(cbuf, bcache))
  end)
end

local function in_git_dir(file: string): boolean
  for _, p in ipairs(vim.split(file, util.path_sep)) do
    if p == '.git' then
      return true
    end
  end
  return false
end

local function on_lines(buf: integer, last_orig: integer, last_new: integer): boolean
  if not cache[buf] then
    dprint('Cache for buffer '..buf..' was nil. Detaching')
    return true
  end

  -- If lines are removed, make sure to immediately remove the signs
  -- This is only has noticeable effect on large files
  if last_new < last_orig then
    for i = last_new+1, last_orig do
      signs.remove(buf, i)
    end
  end

  update_debounced(buf)
end

local attach = async(function(cbuf: integer)
  await(scheduler())
  cbuf = cbuf or current_buf()
  if cache[cbuf] ~= nil then
    dprint('Already attached', cbuf, 'attach')
    return
  end
  dprint('Attaching', cbuf, 'attach')

  local lc = api.nvim_buf_line_count(cbuf)
  if lc > config.max_file_length then
    dprint('Exceeds max_file_length', cbuf, 'attach')
    return
  end

  if api.nvim_buf_get_option(cbuf, 'buftype') ~= '' then
    dprint('Non-normal buffer', cbuf, 'attach')
    return
  end

  local file = get_buf_path(cbuf)

  if in_git_dir(file) then
    dprint('In git dir', cbuf, 'attach')
    return
  end

  local file_dir = util.dirname(file)

  if not file_dir or not util.path_exists(file_dir) then
    dprint('Not a path', cbuf, 'attach')
    return
  end

  local toplevel, gitdir, abbrev_head = await(git.get_repo_info(file_dir))

  if not gitdir then
    dprint('Not in git repo', cbuf, 'attach')
    return
  end

  Status:update_head(cbuf, abbrev_head)

  if not util.path_exists(file) or uv.fs_stat(file).type == 'directory' then
    dprint('Not a file', cbuf, 'attach')
    return
  end

  -- On windows os.tmpname() crashes in callback threads so initialise this
  -- variable on the main thread.
  await(scheduler())
  local staged = os.tmpname() -- Temp filename of staged file

  local relpath, object_name, mode_bits, has_conflicts =
    await(git.file_info(file, toplevel))

  if not relpath then
    dprint('Cannot resolve file in repo', cbuf, 'attach')
    return
  end

  cache[cbuf] = {
    file          = file,
    relpath       = relpath,
    object_name   = object_name,
    mode_bits     = mode_bits,
    toplevel      = toplevel,
    gitdir        = gitdir,
    abbrev_head   = abbrev_head,
    username      = await(git.command{'config', 'user.name'})[1],
    has_conflicts = has_conflicts,
    staged        = staged,
    staged_text   = nil,
    hunks         = {},
    staged_diffs  = {},
    index_watcher = watch_index(cbuf, gitdir, index_update_handler(cbuf))
  }

  -- Initial update
  await(update(cbuf, cache[cbuf]))

  await(scheduler())

  api.nvim_buf_attach(cbuf, false, {
    on_lines = function(_, buf: integer, _, _, last_orig: integer, last_new: integer)
      on_lines(buf, last_orig, last_new)
    end,
    on_detach = function(_, buf: integer)
      detach(buf, true)
    end
  })

  apply_keymaps(true)
end)

local attach_throttled = void(attach)

local function setup_signs_and_highlights(redefine: boolean)
  -- Define signs
  for t, sign_name in pairs(signs.sign_map) do
    local cs = config.signs[t]

    gs_hl.setup_highlight(cs.hl)

    local enum HlTy 'numhl' 'linehl' end
    for _, hlty in ipairs({'numhl', 'linehl'} as {HlTy}) do
      if config[hlty] then
        gs_hl.setup_other_highlight(cs[hlty], cs.hl)
      end
    end

    signs.define(sign_name, {
      texthl = cs.hl,
      text   = config.signcolumn and cs.text or nil,
      numhl  = config.numhl      and cs.numhl,
      linehl = config.linehl     and cs.linehl
    }, redefine)

  end
  if config.current_line_blame then
    gs_hl.setup_highlight('GitSignsCurrentLineBlame')
  end
end

local function add_debug_functions()
  M.dump_cache = function()
    api.nvim_echo({{vim.inspect(cache)}}, false, {})
  end

  M.debug_messages = function(noecho: boolean): {string}
    if not noecho then
      for _, m in ipairs(gs_debug.messages) do
        api.nvim_echo({{m}}, false, {})
      end
    end
    return gs_debug.messages
  end

  M.clear_debug = function()
    gs_debug.messages = {}
  end
end

-- Needs to be global so can be accessed from v:lua
function gitsigns_complete(arglead: string, line: string): {string}
  local n: integer = #vim.split(line, '%s+')

  local matches: {string} = {}
  if n == 2 then
    for func, _ in pairs(M) do
      if vim.startswith(func, '_') then
        -- exclude
      elseif vim.startswith(func, arglead) then
        table.insert(matches, func)
      end
    end
  end
  return matches
end


local function setup_command()
  vim.cmd(table.concat({
    'command!',
    '-nargs=+',
    '-complete=customlist,v:lua.gitsigns_complete',
    'Gitsigns',
    'lua require("gitsigns")._run_func(<f-args>)'
  }, ' '))
end

local function setup_decoration_provider()
  api.nvim_set_decoration_provider(namespace, {
    on_win = function(_, _, bufnr: integer, top: integer, bot: integer): boolean
      local bcache = cache[bufnr]
      if not bcache or not bcache.pending_signs then
        return
      end
      apply_win_signs(bufnr, bcache.pending_signs, top, bot)
    end
  })
end

local function setup_current_line_blame()
  vim.cmd('augroup gitsigns_blame | autocmd! | augroup END')
  if config.current_line_blame then
    for func, events in pairs{
      _current_line_blame       = 'CursorHold',
      _current_line_blame_reset = 'CursorMoved',
    } do
      vim.cmd('autocmd gitsigns_blame '..events..' * lua require("gitsigns").'..func..'()')
    end
  end
end

local setup = void_async(function(cfg: Config)
  config = gs_config.process(cfg)
  namespace = api.nvim_create_namespace('gitsigns')

  gs_debug.debug_mode = config.debug_mode

  if config.debug_mode then
    add_debug_functions()
  end

  Status.formatter = config.status_formatter as function(Status.StatusObj): string

  setup_signs_and_highlights()
  setup_command()
  apply_keymaps(false)

  update_debounced = debounce_trailing(config.update_debounce, void(update))
    as function(integer)

  if config.use_decoration_api then
    -- Calling this before any await calls will stop nvim's intro messages being
    -- displayed
    setup_decoration_provider()
  end

  await(git.set_version(config._git_version))
  await(scheduler())

  -- Attach to all open buffers
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if    api.nvim_buf_is_valid(buf)
      and api.nvim_buf_is_loaded(buf)
      and api.nvim_buf_get_name(buf) ~= '' then
      await(attach(buf))
      await(scheduler())
    end
  end

  -- set up augroup, clear it if setup is run twice.
  vim.cmd('augroup gitsigns | autocmd! | augroup END')

  for func, events in pairs{
    attach             = 'BufRead,BufNewFile,BufWritePost',
    detach_all         = 'VimLeavePre',
    _update_highlights = 'ColorScheme',
  } do
    vim.cmd('autocmd gitsigns '..events..' * lua require("gitsigns").'..func..'()')
  end

  setup_current_line_blame()
end)

local function preview_hunk()
  local cbuf = current_buf()
  local hunk = get_cursor_hunk(cbuf)

  if not hunk then
    return
  end

  local winid, bufnr = gs_popup.create(hunk.lines, { relative = 'cursor' })

  api.nvim_buf_set_option(bufnr, 'tabstop', api.nvim_buf_get_option(cbuf, 'tabstop'))
  api.nvim_buf_set_option(bufnr, 'filetype', 'diff')
  api.nvim_win_set_option(winid, 'number', false)
  api.nvim_win_set_option(winid, 'relativenumber', false)
  api.nvim_win_set_option(winid, 'signcolumn', 'no')
  api.nvim_win_set_option(winid, 'cursorline', false)
end

local function select_hunk()
  local hunk = get_cursor_hunk()
  if not hunk then
    return
  end

  local start, dend = gs_hunks.get_range(hunk)

  vim.cmd('normal! '..start..'GV'..dend..'G')
end

local blame_line = void_async(function()
  local bufnr = current_buf()
  local bcache = cache[bufnr]
  if not bcache then
    return
  end

  local buftext = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local lnum = api.nvim_win_get_cursor(0)[1]
  local result = await(git.run_blame(bcache.file, bcache.toplevel, buftext, lnum))

  local date = os.date('%Y-%m-%d %H:%M', tonumber(result['author_time']))
  local lines = {
    ('%s %s (%s):'):format(result.abbrev_sha, result.author, date),
    result.summary
  }

  await(scheduler())

  local winid, pbufnr = gs_popup.create(lines, { relative = 'cursor', col = 1 })

  api.nvim_win_set_option(winid, 'number', false)
  api.nvim_win_set_option(winid, 'relativenumber', false)

  local p1 = #result.abbrev_sha
  local p2 = #result.author
  local p3 = #date

  local function add_highlight(hlgroup: string, line: integer, start: integer, length: integer)
    api.nvim_buf_add_highlight(pbufnr, -1, hlgroup, line, start, start+length)
  end

  add_highlight('Directory', 0, 0      , p1)
  add_highlight('MoreMsg'  , 0, p1+1   , p2)
  add_highlight('Label'    , 0, p1+p2+2, p3+2)
end)

local _current_line_blame_reset = function(bufnr: integer)
  bufnr = bufnr or current_buf()
  api.nvim_buf_del_extmark(bufnr, namespace, 1)
end

local _current_line_blame = void_async(function()
  local bufnr = current_buf()
  local bcache = cache[bufnr]
  if not bcache or not bcache.object_name then
    return
  end

  local buftext = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local lnum = api.nvim_win_get_cursor(0)[1]
  local result = await(git.run_blame(bcache.file, bcache.toplevel, buftext, lnum))

  await(scheduler())

  _current_line_blame_reset(bufnr)
  api.nvim_buf_set_extmark(bufnr, namespace, lnum-1, 0, {
    id = 1,
    virt_text = config.current_line_blame_formatter(bcache.username, result),
  })
end)

local function refresh()
  setup_signs_and_highlights(true)
  setup_current_line_blame()
  for k, v in pairs(cache) do
    _current_line_blame_reset(k)
    v.staged_text = nil  -- Invalidate
    void(update)(k, v)
  end
end

local function toggle_signs()
  config.signcolumn = not config.signcolumn
  refresh()
end

local function toggle_numhl()
  config.numhl = not config.numhl
  refresh()
end

local function toggle_linehl()
  config.linehl = not config.linehl
  refresh()
end

local function toggle_current_line_blame()
  config.current_line_blame = not config.current_line_blame
  refresh()
end

M = {
  update          = update_debounced,
  stage_hunk      = mk_repeatable(stage_hunk),
  undo_stage_hunk = mk_repeatable(undo_stage_hunk),
  reset_hunk      = mk_repeatable(reset_hunk),
  next_hunk       = next_hunk,
  prev_hunk       = prev_hunk,
  select_hunk     = select_hunk,
  preview_hunk    = preview_hunk,
  blame_line      = blame_line,
  reset_buffer    = reset_buffer,
  attach          = attach_throttled,
  detach          = detach,
  detach_all      = detach_all,
  setup           = setup,
  refresh         = refresh,
  toggle_signs    = toggle_signs,
  toggle_linehl   = toggle_linehl,
  toggle_numhl    = toggle_numhl,

  _current_line_blame       = _current_line_blame,
  _current_line_blame_reset = _current_line_blame_reset,
  toggle_current_line_blame = toggle_current_line_blame,

  _update_highlights = function()
    setup_signs_and_highlights()
  end,
  _run_func = function(func: string, ...: any)
    M[func](...)
  end
}

return M
