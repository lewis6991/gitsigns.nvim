local a = require('plenary.async')
local void      = a.void
local scheduler = a.util.scheduler

local Status     = require("gitsigns.status")
local git        = require('gitsigns.git')
local manager    = require('gitsigns.manager')
local signs      = require('gitsigns.signs')
local util       = require('gitsigns.util')

local gs_cache   = require('gitsigns.cache')
local cache      = gs_cache.cache
local CacheEntry = gs_cache.CacheEntry

local gs_config  = require('gitsigns.config')
local Config     = gs_config.Config
local config     = gs_config.config

local gs_debug   = require("gitsigns.debug")
local dprint     = gs_debug.dprint

local api = vim.api
local uv = vim.loop
local current_buf = api.nvim_get_current_buf

local record M
  setup      : function(cfg: Config)
  detach     : function(bufnr: integer, keep_signs: boolean)
  detach_all : function()
  attach     : function(cbuf: integer)

  -- Internal, API unstable
  _get_config        : function(): Config
  _update_highlights : function()
  _run_func          : function(range: {integer, integer}, func: string, ...: any)
  _complete          : function(arglead: string, line: string): {string}
end

local namespace: integer

local handle_moved = function(bufnr: integer, bcache: CacheEntry, old_relpath: string)
  local git_obj = bcache.git_obj
  local do_update = false

  local new_name = git_obj:has_moved()
  if new_name then
    dprint('File moved to '..new_name, bufnr)
    git_obj.relpath = new_name
    if not git_obj.orig_relpath then
      git_obj.orig_relpath = old_relpath
    end
    do_update = true
  elseif git_obj.orig_relpath then
    local orig_file = git_obj.toplevel..util.path_sep..git_obj.orig_relpath
    if git_obj:file_info(orig_file) then
      dprint('Moved file reset', bufnr)
      git_obj.relpath = git_obj.orig_relpath
      git_obj.orig_relpath = nil
      do_update = true
    end
  else
    -- File removed from index, do nothing
  end

  if do_update then
    git_obj.file = git_obj.toplevel..util.path_sep..git_obj.relpath
    bcache.file = git_obj.file
    bcache.git_obj:update_file_info()
    scheduler()
    api.nvim_buf_set_name(bufnr, bcache.file)
  end
end

local watch_index = function(bufnr: integer, gitdir: string): uv.FSPollObj
  dprint('Watching index', bufnr, 'watch_index')
  local index = gitdir..util.path_sep..'index'
  local w = uv.new_fs_poll()
  w:start(index, config.watch_index.interval, void(function(err: string)
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

    git_obj:update_abbrev_head()

    scheduler()
    Status:update(bufnr, { head = git_obj.abbrev_head})

    local was_tracked = git_obj.object_name ~= nil
    local old_relpath = git_obj.relpath

    if not git_obj:update_file_info() then
      dprint('File not changed', bufnr, 'watcher_cb')
      return
    end

    if config.watch_index.follow_files and was_tracked and not git_obj.object_name then
      -- File was tracked but is no longer tracked. Must of been removed or
      -- moved. Check if it was moved and switch to it.
      handle_moved(bufnr, bcache, old_relpath)
    end

    bcache.compare_text = nil -- Invalidate

    manager.update(bufnr, bcache)
  end))
  return w
end

-- When this is called interactively (with no arguments) we want to remove all
-- the signs, however if called via a detach event (due to nvim_buf_attach) then
-- we don't want to clear the signs in case the buffer is just being updated due
-- to the file externally changing. When this happens a detach and attach event
-- happen in sequence and so we keep the old signs to stop the sign column width
-- moving about between updates.
M.detach = function(bufnr: integer, keep_signs: boolean)
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

  cache:destroy(bufnr)
end

M.detach_all = function()
  for k, _ in pairs(cache as {integer:CacheEntry}) do
    M.detach(k)
  end
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

local attach0 = function(cbuf: integer)
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

  local git_obj = git.Obj.new(file)

  if not git_obj.gitdir then
    dprint('Not in git repo', cbuf, 'attach')
    return
  end

  scheduler()
  Status:update(cbuf, {
    head   = git_obj.abbrev_head,
    root   = git_obj.toplevel,
    gitdir = git_obj.gitdir,
  })

  if vim.startswith(file, git_obj.gitdir..util.path_sep) then
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
  scheduler()

  if config.on_attach and config.on_attach(cbuf) == false then
    dprint('User on_attach() returned false', cbuf, 'attach')
    return
  end

  cache[cbuf] = CacheEntry.new {
    file          = file,
    commit        = commit,
    index_watcher = watch_index(cbuf, git_obj.gitdir),
    git_obj       = git_obj
  }

  -- Initial update
  manager.update(cbuf, cache[cbuf])

  scheduler()

  api.nvim_buf_attach(cbuf, false, {
    on_lines = function(_, buf: integer, _, first: integer, last_orig: integer, last_new: integer, byte_count: integer): boolean
      if first == last_orig and last_orig == last_new and byte_count == 0 then
        -- on_lines can be called twice for undo events; ignore the second
        -- call which indicates no changes.
        return
      end
      return manager.on_lines(buf, last_orig, last_new)
    end,
    on_reload = function(_, buf: integer)
      dprint('Reload', buf, 'on_reload')
      manager.update_debounced(buf)
    end,
    on_detach = function(_, buf: integer)
      M.detach(buf, true)
    end
  })

  if config.keymaps and not vim.tbl_isempty(config.keymaps) then
    require('gitsigns.mappings')(config.keymaps as {string:any})
  end
end

-- Ensure attaches cannot be interleaved.
-- Since attaches are asynchronous we need to make sure an attach isn't
-- performed whilst another one is in progress.
local attach_running: {integer:boolean} = {}

local attach = function(cbuf: integer)
  cbuf = cbuf or current_buf()
  if attach_running[cbuf] then
    dprint('Attach in progress', cbuf, 'attach')
    return
  end
  attach_running[cbuf] = true
  attach0(cbuf)
  attach_running[cbuf] = nil
end

local M0 = M as {string:function}

-- Needs to be global so can be accessed from v:lua
M._complete = function(arglead: string, line: string): {string}
  local n: integer = #vim.split(line, '%s+')

  local matches: {string} = {}
  if n == 2 then
    local function get_matches(t: {string:any})
      for func, _ in pairs(t) do
        if vim.startswith(func, '_') then
          -- exclude
        elseif vim.startswith(func, arglead) then
          table.insert(matches, func)
        end
      end
    end

    get_matches(require('gitsigns.actions') as {string:function})
    get_matches(M0)
  end
  return matches
end

M._run_func = function(range: {integer, integer}, func: string, ...: any)
  local actions = require('gitsigns.actions') as {string:function}
  actions._set_user_range(range)
  if type(actions[func]) == 'function' then
    actions[func](...)
    return
  end
  if type(M0[func]) == 'function' then
    M0[func](...)
    return
  end
end

local function setup_command()
  vim.cmd(table.concat({
    'command!',
    '-range',
    '-nargs=+',
    '-complete=customlist,v:lua.package.loaded.gitsigns._complete',
    'Gitsigns',
    'lua require("gitsigns")._run_func({<line1>, <line2>}, <f-args>)'
  }, ' '))
end

M.setup = void(function(cfg: Config)
  gs_config.build(cfg)
  namespace = api.nvim_create_namespace('gitsigns')

  gs_debug.debug_mode = config.debug_mode

  if config.debug_mode then
    for nm, f in pairs(gs_debug.add_debug_functions(cache)) do
      M0[nm] = f
    end
  end

  manager.setup()

  Status.formatter = config.status_formatter as function(Status.StatusObj): string

  -- Make sure highlights are setup on or after VimEnter so the colorscheme is
  -- loaded. Do not set them up with vim.schedule as this removes the intro
  -- message.
  if vim.v.vim_did_enter == 1 then
    manager.setup_signs_and_highlights()
  else
    vim.cmd[[autocmd VimEnter * ++once lua require('gitsigns.manager').setup_signs_and_highlights()]]
  end

  setup_command()

  if config.use_decoration_api then
    -- Calling this before any await calls will stop nvim's intro messages being
    -- displayed
    api.nvim_set_decoration_provider(namespace, {
      on_win = function(_, _, bufnr: integer, top: integer, bot: integer): boolean
        local bcache = cache[bufnr]
        if not bcache or not bcache.pending_signs then
          return false
        end
        manager.apply_win_signs(bufnr, bcache.pending_signs, top+1, bot+1)

        -- Returning false prevents the on_line callbacks
        return config.word_diff
      end,
      on_line = function(_, _, bufnr: integer, row: integer)
        manager.apply_word_diff(bufnr, row)
      end
    })
  end

  git.enable_yadm = config.yadm.enable
  git.set_version(config._git_version)
  scheduler()

  -- Attach to all open buffers
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if    api.nvim_buf_is_loaded(buf)
      and api.nvim_buf_get_name(buf) ~= '' then
      attach(buf)
      scheduler()
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

  require('gitsigns.current_line_blame').setup()
end)

M.attach = void(attach)

-- Internal, API unstable
M._get_config = function(): Config
  return config
end

M._update_highlights = function()
  manager.setup_signs_and_highlights()
end

setmetatable(M, {
  __index = function(_, f: string): any
    return (require('gitsigns.actions') as {string:function})[f]
  end
})

return M
