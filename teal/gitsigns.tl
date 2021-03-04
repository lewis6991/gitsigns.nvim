local gs_async = require('gitsigns/async')
local async      = gs_async.async
local sync       = gs_async.sync
local arun       = gs_async.arun
local await      = gs_async.await
local await_main = gs_async.await_main

local gs_debounce = require('gitsigns/debounce')
local throttle_leading  = gs_debounce.throttle_leading
local debounce_trailing = gs_debounce.debounce_trailing

local gs_popup = require('gitsigns/popup')

local sign_define    = require('gitsigns/signs').sign_define
local process_config = require('gitsigns/config').process
local mk_repeatable  = require('gitsigns/repeat').mk_repeatable

local apply_mappings = require('gitsigns/mappings')

local git = require('gitsigns/git')
local util = require('gitsigns/util')

local gs_hunks = require("gitsigns/hunks")
local create_patch  = gs_hunks.create_patch
local process_hunks = gs_hunks.process_hunks

local gsd = require("gitsigns/debug")
local dprint = gsd.dprint

local Status = require("gitsigns/status")

local api = vim.api
local uv = vim.loop
local current_buf = api.nvim_get_current_buf

local sign_map: {SignType:SignName} = {
  add          = "GitSignsAdd",
  delete       = "GitSignsDelete",
  change       = "GitSignsChange",
  topdelete    = "GitSignsTopDelete",
  changedelete = "GitSignsChangeDelete",
}

local config: Config

local path_sep = (function(): string
  if jit then
    local jit_os = jit.os:lower()
    if jit_os == 'linux' or jit_os == 'osx' then
      return '/'
    else
      return '\\'
    end
  else
    return package.config:sub(1, 1)
  end
end)()

local function dirname(file: string): string
  return file:match(string.format('^(.+)%s[^%s]+', path_sep, path_sep))
end

local cache: {number:CacheEntry} = {}

local function get_cache(bufnr: number): CacheEntry
  return cache[bufnr]
end

local function get_cache_opt(bufnr: number): CacheEntry
  return cache[bufnr]
end

local function get_cursor_hunk(bufnr: number, hunks: {Hunk}): Hunk
  bufnr = bufnr or current_buf()
  hunks = hunks or cache[bufnr].hunks

  local lnum = api.nvim_win_get_cursor(0)[1]
  return gs_hunks.find_hunk(lnum, hunks)
end

local function add_signs(bufnr: number, signs: {Sign}, reset: boolean)
  reset = reset or false

  if reset then
    vim.fn.sign_unplace('gitsigns_ns', {buffer = bufnr})
  end

  for _, s in ipairs(signs) do
    local stype: string = sign_map[s.type]
    local count = s.count

    local cs = config.signs[s.type]
    if cs.show_count and count then
      local cc = config.count_chars
      local count_suffix: string = cc[count] and (count as string) or (cc['+'] and 'Plus') or ''
      local count_char   = cc[count]           or cc['+']            or ''
      stype = stype..count_suffix
      sign_define(stype, {
        texthl = cs.hl,
        text   = cs.text..count_char,
        numhl  = config.numhl  and cs.numhl,
        linehl = config.linehl and cs.linehl
      })
    end

    vim.fn.sign_place(s.lnum, 'gitsigns_ns', stype, bufnr, {
      lnum = s.lnum, priority = config.sign_priority
    })
  end
end

local update_cnt = 0

local update = async(function(bufnr: number)
  local bcache = get_cache_opt(bufnr)
  if not bcache then
    error('Cache for buffer '..bufnr..' was nil')
    return
  end

  local stage = bcache.has_conflicts and 1 or 0
  await(git.get_staged, bcache.toplevel, bcache.relpath, stage, bcache.staged)

  await_main()
  local buftext = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  bcache.hunks = await(git.run_diff, bcache.staged, buftext, config.diff_algorithm) as {Hunk}

  local status: StatusObj = gs_hunks.get_summary(bcache.hunks)
  status.head = bcache.abbrev_head

  local signs: {Sign} = process_hunks(bcache.hunks)

  await_main()

  add_signs(bufnr, signs, true)

  Status:update(bufnr, status)

  update_cnt = update_cnt + 1
  dprint(string.format('updates: %s, jobs: %s', update_cnt, util.job_cnt), bufnr, 'update')
end)

-- Define in setup so it can be debounced on updatetime
local update_debounced: function(number)

local watch_index = async(function(bufnr: number, gitdir: string, on_change: function): uv.FSPollObj
  -- TODO: Buffers of the same git repo can share an index watcher
  dprint('Watching index', bufnr, 'watch_index')

  local index = gitdir..path_sep..'index'
  local w = uv.new_fs_poll()
  w:start(index, config.watch_index.interval, on_change)

  return w
end)

local add_to_index = async(function(bcache: CacheEntry)
  local relpath, toplevel = bcache.relpath, bcache.toplevel

  await(git.add_file, toplevel, relpath)

  -- Update the cache
  _, bcache.object_name, bcache.mode_bits, bcache.has_conflicts =
    await(git.file_info, relpath, toplevel) as (string, string, string, boolean)
end)

local stage_hunk = sync(function()
  local bufnr = current_buf()

  local bcache = get_cache_opt(bufnr)
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

  if not bcache.object_name then
    -- If there is no object_name then it is not yet in the index so add it
    await(add_to_index, bcache)
  end

  local lines = create_patch(bcache.relpath, hunk, bcache.mode_bits)

  await(git.stage_lines, bcache.toplevel, lines)

  table.insert(bcache.staged_diffs, hunk)

  local signs = process_hunks({hunk})

  await_main()

  -- If watch_index is enabled then that will eventually kick in and update the
  -- signs, however for  smoother UX we can update the signs immediately without
  -- running a full diff.
  --
  -- We cannot update the status bar as that requires a full diff.
  for _, s in ipairs(signs) do
    vim.fn.sign_unplace('gitsigns_ns', {buffer = bufnr, id = s.lnum})
  end
end)

local function reset_hunk()
  local bufnr = current_buf()

  local bcache = get_cache_opt(bufnr)
  if not bcache then
    return
  end

  local hunk = get_cursor_hunk(bufnr, bcache.hunks)
  if not hunk then
    return
  end

  local lstart, lend: number, number
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

local undo_stage_hunk = sync(function()
  local bufnr = current_buf()

  local bcache = get_cache_opt(bufnr)
  if not bcache then
    return
  end

  local hunk = bcache.staged_diffs[#bcache.staged_diffs]

  if not hunk then
    print("No hunks to undo")
    return
  end

  local lines = create_patch(bcache.relpath, hunk, bcache.mode_bits, true)

  await(git.stage_lines, bcache.toplevel, lines)

  table.remove(bcache.staged_diffs)

  local signs = process_hunks({hunk})

  await_main()
  add_signs(bufnr, signs)
end)

local record NavHunkOpts
  forwards: boolean
  wrap: boolean
end

local function nav_hunk(options: NavHunkOpts)
  local bcache = get_cache_opt(current_buf())
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

local function detach(bufnr: number)
  bufnr = bufnr or current_buf()
  dprint('Detached', bufnr)

  local bcache = get_cache_opt(bufnr)
  if not bcache then
    dprint('Cache was nil', bufnr)
    return
  end

  -- Remove all the signs
  vim.fn.sign_unplace('gitsigns_ns', {buffer = bufnr})

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
  apply_mappings(config.keymaps as {string:uany}, bufonly)
end

local function get_buf_path(bufnr: number): string
  return
    uv.fs_realpath(api.nvim_buf_get_name(bufnr))
    or
    api.nvim_buf_call(bufnr, function(): string
      return vim.fn.expand('%:p')
    end)
end

local function index_update_handler(cbuf: number): function
  return sync(function()
    dprint('Index update', cbuf, 'watcher_cb')
    local bcache = get_cache(cbuf)
    local file_dir = dirname(bcache.file)

    local _, _, abbrev_head0 =
      await(git.get_repo_info, file_dir) as (string, string, string)

    Status:update_head(cbuf, abbrev_head0)
    bcache.abbrev_head = abbrev_head0

    local _, object_name0, mode_bits0, has_conflicts =
      await(git.file_info, bcache.file, bcache.toplevel) as (string, string, string, boolean)

    if object_name0 == bcache.object_name then
      dprint('File not changed', cbuf, 'watcher_cb')
      return
    end

    bcache.object_name = object_name0
    bcache.mode_bits = mode_bits0
    bcache.has_conflicts = has_conflicts

    await(update, cbuf)
  end)
end

local function in_git_dir(file: string): boolean
  for _, p in ipairs(vim.split(file, path_sep)) do
    if p == '.git' then
      return true
    end
  end
  return false
end

local function on_lines(buf: number): boolean
  if not get_cache_opt(buf) then
    dprint('Cache for buffer '..buf..' was nil. Detaching')
    return true
  end
  update_debounced(buf)
end

local attach = throttle_leading(100, sync(function()
  local cbuf = current_buf()
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

  local file_dir = dirname(file)

  if not file_dir or not util.path_exists(file_dir) then
    dprint('Not a path', cbuf, 'attach')
    return
  end

  local toplevel, gitdir, abbrev_head =
    await(git.get_repo_info, file_dir) as (string, string, string)

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
  await_main()
  local staged = os.tmpname() -- Temp filename of staged file

  local relpath, object_name, mode_bits, has_conflicts =
    await(git.file_info, file, toplevel) as (string, string, string, boolean)

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
    has_conflicts = has_conflicts,
    staged        = staged,
    hunks         = {},
    staged_diffs  = {},
    index_watcher = await(watch_index, cbuf, gitdir, index_update_handler(cbuf))
      as uv.FSPollObj
  }

  -- Initial update
  await(update, cbuf)

  await_main()

  api.nvim_buf_attach(cbuf, false, {
    on_lines = function(_, buf: number)
      on_lines(buf)
    end,
    on_detach = function(_, buf: number)
      detach(buf)
    end
  })

  apply_keymaps(true)
end))

local function setup(cfg: Config)
  config = process_config(cfg) as Config

  -- TODO: Attach to all open buffers

  gsd.debug_mode = config.debug_mode

  Status.formatter = config.status_formatter

  -- Define signs
  for t, sign_name in pairs(sign_map) do
    local cs = config.signs[t]

    local enum HlTy 'numhl' 'linehl' end

    for _, hl in ipairs({'numhl', 'linehl'} as {HlTy}) do
      if config[hl] then
        local hl_exists, _ = pcall(api.nvim_get_hl_by_name, cs[hl], false)
        if not hl_exists then
          vim.cmd(('highlight link %s %s'):format(cs[hl], cs.hl))
        end
      end
    end

    sign_define(sign_name, {
      texthl = cs.hl,
      text   = cs.text,
      numhl  = config.numhl  and cs.numhl,
      linehl = config.linehl and cs.linehl
    })

  end

  apply_keymaps(false)

  update_debounced = debounce_trailing(config.update_debounce, arun(update))
    as function(number)

  -- This seems to be triggered twice on the first buffer so we have throttled
  -- the attach function with throttle_leading
  vim.cmd('autocmd BufRead,BufNewFile,BufWritePost '..
    '* lua require("gitsigns").attach()')

  vim.cmd('autocmd VimLeavePre * lua require("gitsigns").detach_all()')
end

local function preview_hunk()
  local hunk = get_cursor_hunk()

  if not hunk then
    return
  end

  local winid, bufnr = gs_popup.create(hunk.lines, { relative = 'cursor' })

  api.nvim_buf_set_option(bufnr, 'filetype', 'diff')
  api.nvim_win_set_option(winid, 'number', false)
  api.nvim_win_set_option(winid, 'relativenumber', false)
end

local function text_object()
  local hunk = get_cursor_hunk()
  if not hunk then
    return
  end

  local start, dend = gs_hunks.get_range(hunk)

  vim.cmd('normal! '..start..'GV'..dend..'G')
end

local blame_line = sync(function()
  local bufnr = current_buf()

  local bcache = get_cache_opt(bufnr)
  if not bcache then
    return
  end

  local buftext = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local lnum = api.nvim_win_get_cursor(0)[1]
  local result = await(git.run_blame, bcache.file, bcache.toplevel, buftext, lnum) as {string:string}

  local date = os.date('%Y-%m-%d %H:%M', tonumber(result['author-time']))
  local lines = {
    ('%s %s (%s):'):format(result.abbrev_sha, result.author, date),
    result.summary
  }

  await_main()

  local winid, pbufnr = gs_popup.create(lines, { relative = 'cursor', col = 1 })

  api.nvim_win_set_option(winid, 'number', false)
  api.nvim_win_set_option(winid, 'relativenumber', false)

  local p1 = #result.abbrev_sha
  local p2 = #result.author
  local p3 = #date

  local function add_highlight(hlgroup: string, line: number, start: number, length: number)
    api.nvim_buf_add_highlight(pbufnr, -1, hlgroup, line, start, start+length)
  end

  add_highlight('Directory', 0, 0      , p1)
  add_highlight('MoreMsg'  , 0, p1+1   , p2)
  add_highlight('Label'    , 0, p1+p2+2, p3+2)
end)

local function dump_cache()
  print(vim.inspect(cache))
end

return {
  update          = update_debounced,
  stage_hunk      = mk_repeatable(stage_hunk),
  undo_stage_hunk = mk_repeatable(undo_stage_hunk),
  reset_hunk      = mk_repeatable(reset_hunk),
  next_hunk       = next_hunk,
  prev_hunk       = prev_hunk,
  preview_hunk    = preview_hunk,
  blame_line      = blame_line,
  attach          = attach,
  detach          = detach,
  detach_all      = detach_all,
  setup           = setup,
  text_object     = text_object,
  dump_cache      = dump_cache
}
