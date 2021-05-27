local a = require('plenary.async_lib.async')
local void       = a.void
local await      = a.await
local async      = a.async
local async_void = a.async_void
local scheduler  = a.scheduler

local sleep = require('plenary.async_lib.util').sleep

local gs_debounce       = require('gitsigns.debounce')
local debounce_trailing = gs_debounce.debounce_trailing

local gs_hl             = require('gitsigns.highlight')

local signs             = require('gitsigns.signs')
local Sign              = signs.Sign

local gs_config         = require('gitsigns.config')
local Config            = gs_config.Config

local mk_repeatable     = require('gitsigns.repeat').mk_repeatable

local apply_mappings    = require('gitsigns.mappings')

local git               = require('gitsigns.git')
local util              = require('gitsigns.util')

local gs_hunks          = require("gitsigns.hunks")
local process_hunks     = gs_hunks.process_hunks
local Hunk              = gs_hunks.Hunk

local gs_debug          = require("gitsigns.debug")
local dprint            = gs_debug.dprint

local Status            = require("gitsigns.status")

local api = vim.api
local uv = vim.loop
local current_buf = api.nvim_get_current_buf

local M: {string:function} = {}

local config: Config

local namespace: integer

local record CacheEntry
  file          : string
  compare_file  : string    -- For use with externl diff
  base          : string
  compare_text  : {string}  -- For use with internal diff
  hunks         : {Hunk}
  staged_diffs  : {Hunk}
  pending_signs : {integer:Sign}
  index_watcher : uv.FSPollObj -- Timer object watching the files index
  git_obj       : git.Obj
  commit        : string
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

local update_cnt = 0

local function get_compare_object(bcache: CacheEntry, base: string): string
  base = base or bcache.base
  local prefix: string
  if base then
    prefix = base
  elseif bcache.commit then
    -- Buffer is a fugutive commit so compare against the parent of the commit
    prefix = string.format('%s^', bcache.commit)
  else
    local stage = bcache.git_obj.has_conflicts and 1 or 0
    prefix = string.format(':%d', stage)
  end

  return string.format('%s:%s', prefix, bcache.git_obj.relpath)
end

local update0 = async(function(bufnr: integer, bcache: CacheEntry)
  bcache = bcache or cache[bufnr]
  if not bcache then
    error('Cache for buffer '..bufnr..' was nil')
    return
  end

  await(scheduler())
  local buftext = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local git_obj = bcache.git_obj

  local compare_object = get_compare_object(bcache)

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
  bcache.pending_signs = process_hunks(bcache.hunks)

  await(scheduler())

  -- Apply signs to the window. Other signs will be added by the decoration
  -- provider as they are drawn.
  apply_win_signs(bufnr, bcache.pending_signs)

  Status:update(bufnr, gs_hunks.get_summary(bcache.hunks, git_obj.abbrev_head))

  update_cnt = update_cnt + 1
  dprint(string.format('updates: %s, jobs: %s', update_cnt, util.job_cnt), bufnr, 'update')
end)

-- Ensure updates cannot be interleaved.
-- Since updates are asynchronous we need to make sure an update isn't performed
-- whilst another one is in progress. If this happens then schedule another
-- update after the current one has completed.
local update: a.async_fun1<integer>
do
  local running = false
  local scheduled: {integer:boolean} = {}
  update = async(function(bufnr: integer)
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

-- Define in setup so it can be debounced on updatetime
local update_debounced: function(integer, CacheEntry)

local watch_index = function(bufnr: integer, gitdir: string): uv.FSPollObj
  dprint('Watching index', bufnr, 'watch_index')
  local index = gitdir..util.path_sep..'index'
  local w = uv.new_fs_poll()
  w:start(index, config.watch_index.interval, async_void(function(err: string)
    if err then
      dprint('Index update error: '..err, bufnr, 'watcher_cb')
      return
    end
    dprint('Index update', bufnr, 'watcher_cb')

    local bcache = cache[bufnr]

    if not bcache then
      -- Very occasionally an external git operation may cause the buffer to
      -- detach and update the index simultaneously. When this happens this
      -- handler will trigger but there will be no cache.
      dprint(string.format('Buffer %s has detached, aborting', bufnr))
      return
    end

    local git_obj = bcache.git_obj

    await(git_obj:update_abbrev_head())

    await(scheduler())
    Status:update_head(bufnr, git_obj.abbrev_head)

    if not await(git_obj:update_file_info()) then
      dprint('File not changed', bufnr, 'watcher_cb')
      return
    end

    bcache.compare_text = nil -- Invalidate

    await(update(bufnr))
  end))
  return w
end

local stage_hunk = async_void(function()
  local bufnr = current_buf()
  local bcache = cache[bufnr]
  if not bcache then
    return
  end

  if not util.path_exists(bcache.file) then
    print("Error: Cannot stage lines. Please add the file to the working tree.")
    return
  end

  local hunk = get_cursor_hunk(bufnr, bcache.hunks)
  if not hunk then
    return
  end

  await(bcache.git_obj:stage_hunks({hunk}))

  table.insert(bcache.staged_diffs, hunk)
  bcache.compare_text = nil -- Invalidate

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
  await(update(bufnr))
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

local reset_buffer = async_void(function()
  local bufnr = current_buf()
  local bcache = cache[bufnr]
  if not bcache then
    return
  end

  local limit <const> = 1000
  -- Reseting a hunk may change how the rest of the hunks are calculated so we
  -- need to run a full update between each reset.
  for _ = 1, limit do
    if not bcache.hunks[1] then
      return
    end
    reset_hunk(bufnr, bcache.hunks[1])
    await(update(bufnr))
  end
  error('Hit maximum limit of hunks to reset')
end)

local undo_stage_hunk = async_void(function()
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

  await(bcache.git_obj:stage_hunks({hunk}, true))
  bcache.compare_text = nil -- Invalidate
  await(scheduler())
  signs.add(config, bufnr, process_hunks({hunk}))
end)

local stage_buffer = async_void(function()
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

  await(bcache.git_obj:stage_hunks(hunks))

  for _, hunk in ipairs(hunks) do
    table.insert(bcache.staged_diffs, hunk)
  end
  bcache.compare_text = nil -- Invalidate

  await(scheduler())
  signs.remove(bufnr)
  Status:clear_diff(bufnr)
end)

local reset_buffer_index = async_void(function()
  local bufnr = current_buf()
  local bcache = cache[bufnr]
  if not bcache then
    return
  end

  -- `bcache.staged_diffs` won't contain staged changes outside of current
  -- neovim session so signs added from this unstage won't be complete They will
  -- however be fixed by index watcher and properly updated We should implement
  -- some sort of initial population from git diff, after that this function can
  -- be improved to check if any staged hunks exists and it can undo changes
  -- using git apply line by line instead of reseting whole file
  local hunks = bcache.staged_diffs
  bcache.staged_diffs = {}

  await(bcache.git_obj:unstage_file())
  bcache.compare_text = nil -- Invalidate

  await(scheduler())
  signs.add(config, bufnr, process_hunks(hunks))
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
  local row = options.forwards and hunk.start or hunk.vend
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
-- to the file externally changing. When this happens a detach and attach event
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
    signs.remove(bufnr)  -- Remove all signs
  end

  -- Clear status variables
  Status:clear(bufnr)

  os.remove(bcache.compare_file)

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

local function get_buf_path(bufnr: integer): string, string
  local file =
    uv.fs_realpath(api.nvim_buf_get_name(bufnr))
      or
    api.nvim_buf_call(bufnr, function(): string
      return vim.fn.expand('%:p')
    end)

  if vim.startswith(file, 'fugitive://') and vim.wo.diff == false then
    local orig_path = file
    local _,_, root_path, sub_module_path, commit, real_path =
      file:find([[^fugitive://(.*)/%.git(.*)/(%x-)/(.*)]])
    if root_path then
      sub_module_path = sub_module_path:gsub("^/modules", "")
      file = root_path .. sub_module_path .. real_path
      file = uv.fs_realpath(file)
      dprint(("Fugitive buffer for file '%s' from path '%s'"):format(file, orig_path), bufnr)
      if file then
        return file, commit
      else
        file = orig_path
      end
    end
  end

  return file
end

local function in_git_dir(file: string): boolean
  for _, p in ipairs(vim.split(file, util.path_sep)) do
    if p == '.git' then
      return true
    end
  end
  return false
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

local function on_lines(buf: integer, last_orig: integer, last_new: integer): boolean
  if not cache[buf] then
    dprint('Cache for buffer '..buf..' was nil. Detaching')
    return true
  end

  speculate_signs(buf, last_orig, last_new)
  update_debounced(buf)
end

local attach = async(function(cbuf: integer)
  await(scheduler())
  cbuf = cbuf or current_buf()
  if cache[cbuf] then
    dprint('Already attached', cbuf, 'attach')
    return
  end
  dprint('Attaching', cbuf, 'attach')

  if not api.nvim_buf_is_loaded(cbuf) then
    dprint('Non-loaded buffer', cbuf, 'attach')
    return
  end

  if api.nvim_buf_line_count(cbuf) > config.max_file_length then
    dprint('Exceeds max_file_length', cbuf, 'attach')
    return
  end

  if api.nvim_buf_get_option(cbuf, 'buftype') ~= '' then
    dprint('Non-normal buffer', cbuf, 'attach')
    return
  end

  local file, commit = get_buf_path(cbuf)

  if in_git_dir(file) then
    dprint('In git dir', cbuf, 'attach')
    return
  end

  local file_dir = util.dirname(file)

  if not file_dir or not util.path_exists(file_dir) then
    dprint('Not a path', cbuf, 'attach')
    return
  end

  local git_obj = await(git.Obj.new(file))

  if not git_obj.gitdir then
    dprint('Not in git repo', cbuf, 'attach')
    return
  end

  await(scheduler())
  Status:update_head(cbuf, git_obj.abbrev_head)

  if vim.startswith(file, git_obj.gitdir) then
    dprint('In non-standard git dir', cbuf, 'attach')
    return
  end

  if not util.path_exists(file) or uv.fs_stat(file).type == 'directory' then
    dprint('Not a file', cbuf, 'attach')
    return
  end

  if not git_obj.relpath then
    dprint('Cannot resolve file in repo', cbuf, 'attach')
    return
  end

  if not config.attach_to_untracked and git_obj.object_name == nil then
    dprint('File is untracked', cbuf, 'attach')
    return
  end

  -- On windows os.tmpname() crashes in callback threads so initialise this
  -- variable on the main thread.
  await(scheduler())

  cache[cbuf] = {
    file          = file,
    commit        = commit,
    compare_file  = os.tmpname(),
    compare_text  = nil,
    hunks         = {},
    staged_diffs  = {},
    index_watcher = watch_index(cbuf, git_obj.gitdir),
    git_obj       = git_obj
  }

  -- Initial update
  await(update(cbuf))

  await(scheduler())

  api.nvim_buf_attach(cbuf, false, {
    on_lines = function(_, buf: integer, _, first: integer, last_orig: integer, last_new: integer, byte_count: integer): boolean
      if first == last_orig and last_orig == last_new and byte_count == 0 then
        -- on_lines can be called twice for undo events; ignore the second
        -- call which indicates no changes.
        return
      end
      return on_lines(buf, last_orig, last_new)
    end,
    on_reload = function(_, buf: integer)
      dprint('Reload', buf, 'on_reload')
      update_debounced(buf)
    end,
    on_detach = function(_, buf: integer)
      detach(buf, true)
    end
  })

  apply_keymaps(true)
end)

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

-- Needs to be global so can be accessed from v:lua
local function _complete(arglead: string, line: string): {string}
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
    '-complete=customlist,v:lua.package.loaded.gitsigns._complete',
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
      apply_win_signs(bufnr, bcache.pending_signs, top+1, bot+1)
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

local setup = async_void(function(cfg: Config)
  config = gs_config.build(cfg)
  namespace = api.nvim_create_namespace('gitsigns')

  gs_debug.debug_mode = config.debug_mode

  if config.debug_mode then
    for nm, f in pairs(gs_debug.add_debug_functions(cache)) do
      M[nm] = f
    end
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

  git.enable_yadm = config.yadm.enable
  await(git.set_version(config._git_version))
  await(scheduler())

  -- Attach to all open buffers
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if    api.nvim_buf_is_loaded(buf)
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
  local hunk = get_cursor_hunk()
  if not hunk then return end

  local gs_popup = require('gitsigns.popup')

  local _, bufnr = gs_popup.create(hunk.lines, config.preview_config)
  api.nvim_buf_set_option(bufnr, 'filetype', 'diff')
end

local function select_hunk()
  local hunk = get_cursor_hunk()
  if not hunk then return end

  vim.cmd('normal! '..hunk.start..'GV'..hunk.vend..'G')
end

local blame_line = async_void(function(full: boolean)
  local bufnr = current_buf()
  local bcache = cache[bufnr]
  if not bcache then return end

  local buftext = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local lnum = api.nvim_win_get_cursor(0)[1]
  local result = await(bcache.git_obj:run_blame(buftext, lnum))

  local gs_popup = require('gitsigns.popup')

  local is_committed = tonumber('0x'..result.sha) ~= 0
  if is_committed then
    local body = {}
    if full then
      body = await(bcache.git_obj:command({'show', '-s', '--format=%b', result.sha}))

      while body[#body] == '' do
        body[#body] = nil
      end

      if #body > 0 then
        body = {'', unpack(body)}
      end
    end

    local date = os.date('%Y-%m-%d %H:%M', tonumber(result['author_time']))
    local lines = {
      ('%s %s (%s):'):format(result.abbrev_sha, result.author, date),
      result.summary,
      unpack(body)
    }

    await(scheduler())
    local _, pbufnr = gs_popup.create(lines, config.preview_config)

    local p1 = #result.abbrev_sha
    local p2 = #result.author
    local p3 = #date

    local function add_highlight(hlgroup: string, line: integer, start: integer, length: integer)
      api.nvim_buf_add_highlight(pbufnr, -1, hlgroup, line, start, start+length)
    end

    add_highlight('Directory', 0, 0      , p1)
    add_highlight('MoreMsg'  , 0, p1+1   , p2)
    add_highlight('Label'    , 0, p1+p2+2, p3+2)
  else
    local lines = {result.author}
    await(scheduler())
    local _, pbufnr = gs_popup.create(lines, config.preview_config)
    api.nvim_buf_add_highlight(pbufnr, -1, 'MoreMsg', 0, 0, #result.author)
  end
end)

local _current_line_blame_reset = function(bufnr: integer)
  bufnr = bufnr or current_buf()
  api.nvim_buf_del_extmark(bufnr, namespace, 1)
end

local _current_line_blame = async_void(function()
  local bufnr = current_buf()
  local bcache = cache[bufnr]
  if not bcache or not bcache.git_obj.object_name then
    return
  end

  local buftext = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local lnum = api.nvim_win_get_cursor(0)[1]
  local result = await(bcache.git_obj:run_blame(buftext, lnum))

  await(scheduler())

  _current_line_blame_reset(bufnr)
  api.nvim_buf_set_extmark(bufnr, namespace, lnum-1, 0, {
    id = 1,
    virt_text = config.current_line_blame_formatter(bcache.git_obj.username, result),
  })
end)

local function refresh()
  setup_signs_and_highlights(true)
  setup_current_line_blame()
  for k, v in pairs(cache) do
    _current_line_blame_reset(k)
    v.compare_text = nil  -- Invalidate
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

local function calc_base(base: string): string
  if base and base:sub(1, 1):match('[~\\^]') then
    base = 'HEAD'..base
  end
  return base
end

local function change_base(base: string)
  base = calc_base(base)
  local buf = current_buf()
  cache[buf].base = base
  cache[buf].compare_text = nil
  update_debounced(buf)
end

local function get_show_text(bcache: CacheEntry, comp_obj: string): {string}
  if config.use_internal_diff then
    return await(bcache.git_obj:get_show_text(comp_obj))
  end

  local compare_file = os.tmpname()
  await(bcache.git_obj:get_show(comp_obj, compare_file))
  local text = util.file_lines(compare_file)
  os.remove(compare_file)
  return text
end

local function get_bcache_compare_lines(bcache: CacheEntry): {string}
  if config.use_internal_diff then
    return bcache.compare_text
  end
  return util.file_lines(bcache.compare_file)
end

local diffthis = async_void(function(base: string)
  local bufnr = current_buf()
  local bcache = cache[bufnr]
  if not bcache then return end

  if api.nvim_win_get_option(0, 'diff') then return end

  local text: {string}
  local comp_obj = get_compare_object(bcache, calc_base(base))
  if base then
    text = get_show_text(bcache, comp_obj)
  else
    text = get_bcache_compare_lines(bcache)
  end

  await(scheduler())

  local ft = api.nvim_buf_get_option(bufnr, 'filetype')

  local bufname = string.format('gitsigns://%s/%s', bcache.git_obj.gitdir, comp_obj)

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

M = {
  update               = update_debounced,
  stage_hunk           = mk_repeatable(stage_hunk),
  undo_stage_hunk      = mk_repeatable(undo_stage_hunk),
  reset_hunk           = mk_repeatable(reset_hunk),
  stage_buffer         = stage_buffer,
  reset_buffer_index   = reset_buffer_index,
  next_hunk            = next_hunk,
  prev_hunk            = prev_hunk,
  select_hunk          = select_hunk,
  preview_hunk         = preview_hunk,
  blame_line           = blame_line,
  reset_buffer         = reset_buffer,
  change_base          = change_base,
  attach               = void(attach),
  detach               = detach,
  detach_all           = detach_all,
  setup                = setup,
  refresh              = refresh,
  toggle_signs         = toggle_signs,
  toggle_linehl        = toggle_linehl,
  toggle_numhl         = toggle_numhl,

  diffthis             = diffthis,

  -- Internal, API unstable
  _get_config = function(): Config
    return config
  end,

  _complete = _complete,

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
