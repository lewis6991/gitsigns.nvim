local Status = require('gitsigns.status')
local async = require('gitsigns.async')
local git = require('gitsigns.git')
local Cache = require('gitsigns.cache')
local log = require('gitsigns.debug.log')
local manager = require('gitsigns.manager')
local util = require('gitsigns.util')

local cache = Cache.cache
local config = require('gitsigns.config').config
local dprint = log.dprint
local dprintf = log.dprintf
local throttle_by_id = require('gitsigns.debounce').throttle_by_id
local debounce_trailing = require('gitsigns.debounce').debounce_trailing

local api = vim.api
local uv = vim.loop

local M = {}

--- @param name string
--- @return string? buffer
--- @return string? commit
local function parse_fugitive_uri(name)
  if vim.fn.exists('*FugitiveReal') == 0 then
    dprint('Fugitive not installed')
    return
  end

  ---@type string
  local path = vim.fn.FugitiveReal(name)
  ---@type string?
  local commit = vim.fn.FugitiveParse(name)[1]:match('([^:]+):.*')
  if commit == '0' then
    -- '0' means the index so clear commit so we attach normally
    commit = nil
  end
  return path, commit
end

--- @param name string
--- @return string buffer
--- @return string? commit
local function parse_gitsigns_uri(name)
  -- TODO(lewis6991): Support submodules
  --- @type any, any, string?, string?, string
  local _, _, root_path, commit, rel_path = name:find([[^gitsigns://(.*)/%.git/(.*):(.*)]])
  commit = util.norm_base(commit)
  if root_path then
    name = root_path .. '/' .. rel_path
  end
  return name, commit
end

--- @param bufnr integer
--- @return string buffer
--- @return string? commit
--- @return boolean? force_attach
local function get_buf_path(bufnr)
  local file = uv.fs_realpath(api.nvim_buf_get_name(bufnr))
    or api.nvim_buf_call(bufnr, function()
      return vim.fn.expand('%:p')
    end)

  if vim.startswith(file, 'fugitive://') then
    local path, commit = parse_fugitive_uri(file)
    dprintf("Fugitive buffer for file '%s' from path '%s'", path, file)
    if path then
      local realpath = uv.fs_realpath(path)
      if realpath and vim.fn.isdirectory(realpath) == 0 then
        return realpath, commit, true
      end
    end
  end

  if vim.startswith(file, 'gitsigns://') then
    local path, commit = parse_gitsigns_uri(file)
    dprintf("Gitsigns buffer for file '%s' from path '%s' on commit '%s'", path, file, commit)
    local realpath = uv.fs_realpath(path)
    if realpath then
      return realpath, commit, true
    end
  end

  return file
end

local function on_lines(_, bufnr, _, first, last_orig, last_new, byte_count)
  if first == last_orig and last_orig == last_new and byte_count == 0 then
    -- on_lines can be called twice for undo events; ignore the second
    -- call which indicates no changes.
    return
  end
  return manager.on_lines(bufnr, first, last_orig, last_new)
end

--- @param _ 'reload'
--- @param bufnr integer
local function on_reload(_, bufnr)
  local __FUNC__ = 'on_reload'
  cache[bufnr]:invalidate()
  dprint('Reload')
  manager.update_debounced(bufnr)
end

--- @param _ 'detach'
--- @param bufnr integer
local function on_detach(_, bufnr)
  api.nvim_clear_autocmds({ group = 'gitsigns', buffer = bufnr })
  M.detach(bufnr, true)
end

--- @param bufnr integer
--- @return string?
--- @return string?
local function on_attach_pre(bufnr)
  --- @type string?, string?
  local gitdir, toplevel
  if config._on_attach_pre then
    --- @type {gitdir: string?, toplevel: string?}
    local res = async.wait(2, config._on_attach_pre, bufnr)
    dprintf('ran on_attach_pre with result %s', vim.inspect(res))
    if type(res) == 'table' then
      if type(res.gitdir) == 'string' then
        gitdir = res.gitdir
      end
      if type(res.toplevel) == 'string' then
        toplevel = res.toplevel
      end
    end
  end
  return gitdir, toplevel
end

--- @param _bufnr integer
--- @param file string
--- @param revision string?
--- @param encoding string
--- @return Gitsigns.GitObj?
local function try_worktrees(_bufnr, file, revision, encoding)
  if not config.worktrees then
    return
  end

  for _, wt in ipairs(config.worktrees) do
    local git_obj = git.Obj.new(file, revision, encoding, wt.gitdir, wt.toplevel)
    if git_obj and git_obj.object_name then
      dprintf('Using worktree %s', vim.inspect(wt))
      return git_obj
    end
  end
end

local setup = util.once(function()
  manager.setup()

  api.nvim_create_autocmd('OptionSet', {
    group = 'gitsigns',
    pattern = { 'fileformat', 'bomb', 'eol' },
    callback = function()
      local buf = vim.api.nvim_get_current_buf()
      local bcache = cache[buf]
      if not bcache then
        return
      end
      bcache:invalidate(true)
      manager.update(buf)
    end,
  })

  require('gitsigns.current_line_blame').setup()

  api.nvim_create_autocmd('VimLeavePre', {
    group = 'gitsigns',
    callback = M.detach_all,
  })
end)

--- @class Gitsigns.GitContext
--- @field file string
--- @field toplevel? string
--- @field gitdir? string
--- @field base? string

--- @param bufnr integer
--- @return Gitsigns.GitContext? ctx
--- @return string? err
local function get_buf_context(bufnr)
  if api.nvim_buf_line_count(bufnr) > config.max_file_length then
    return nil, 'Exceeds max_file_length'
  end

  local file, commit, force_attach = get_buf_path(bufnr)

  if vim.bo[bufnr].buftype ~= '' and not force_attach then
    return nil, 'Non-normal buffer'
  end

  local file_dir = util.dirname(file)

  if not file_dir or not util.path_exists(file_dir) then
    return nil, 'Not a path'
  end

  local gitdir, toplevel = on_attach_pre(bufnr)

  return {
    file = file,
    gitdir = gitdir,
    toplevel = toplevel,
    -- Stage buffers always compare against the common ancestor (':1')
    -- :0: index
    -- :1: common ancestor
    -- :2: target commit (HEAD)
    -- :3: commit which is being merged
    base = commit and (commit:match('^:[1-3]') and ':1' or commit) or nil,
  }
end

--- @param bufnr integer
--- @param old_relpath string
local function handle_moved(bufnr, old_relpath)
  local bcache = assert(cache[bufnr])
  local git_obj = bcache.git_obj

  local new_name = git_obj:has_moved()
  if new_name then
    dprintf('File moved to %s', new_name)
    git_obj.relpath = new_name
    if not git_obj.orig_relpath then
      git_obj.orig_relpath = old_relpath
    end
  elseif git_obj.orig_relpath then
    local orig_file = git_obj.repo.toplevel .. util.path_sep .. git_obj.orig_relpath
    if not git_obj:file_info(orig_file).relpath then
      return
    end
    --- File was moved in the index, but then reset
    dprintf('Moved file reset')
    git_obj.relpath = git_obj.orig_relpath
    git_obj.orig_relpath = nil
  else
    -- File removed from index, do nothing
    return
  end

  git_obj.file = git_obj.repo.toplevel .. util.path_sep .. git_obj.relpath
  bcache.file = git_obj.file
  git_obj:update()
  if not manager.schedule(bufnr) then
    return
  end

  local bufexists = util.bufexists(bcache.file)
  local old_name = api.nvim_buf_get_name(bufnr)

  if not bufexists then
    -- Do not trigger BufFilePre/Post
    -- TODO(lewis6991): figure out how to avoid reattaching without
    -- disabling all autocommands.
    util.noautocmd({ 'BufFilePre', 'BufFilePost' }, function()
      util.buf_rename(bufnr, bcache.file)
    end)
  end

  local msg = bufexists and 'Cannot rename' or 'Renamed'
  dprintf('%s buffer %d from %s to %s', msg, bufnr, old_name, bcache.file)
end

--- @async
--- @param bufnr integer
local function watcher_handler0(bufnr)
  local __FUNC__ = 'watcher_handler'

  -- Avoid cache hit for detached buffer
  -- ref: https://github.com/lewis6991/gitsigns.nvim/issues/956
  if not manager.schedule(bufnr) then
    dprint('buffer invalid (1)')
    return
  end

  local git_obj = cache[bufnr].git_obj

  Status:update(bufnr, { head = git_obj.repo.abbrev_head })

  local was_tracked = git_obj.object_name ~= nil
  local old_relpath = git_obj.relpath

  git_obj:update()
  if not manager.schedule(bufnr) then
    dprint('buffer invalid (3)')
    return
  end

  if config.watch_gitdir.follow_files and was_tracked and not git_obj.object_name then
    -- File was tracked but is no longer tracked. Must of been removed or
    -- moved. Check if it was moved and switch to it.
    handle_moved(bufnr, old_relpath)
    if not manager.schedule(bufnr) then
      dprint('buffer invalid (4)')
      return
    end
  end

  cache[bufnr]:invalidate(true)

  require('gitsigns.manager').update(bufnr)
end

--- Debounce to:
--- - wait for all changes to the gitdir to complete.
--- Throttle to:
--- - ensure handler is only triggered once per git operation.
--- - prevent updates to the same buffer from interleaving as the handler is
---   async.
local watcher_handler =
  debounce_trailing(200, async.create(1, throttle_by_id(watcher_handler0, true)), 1)

--- Ensure attaches cannot be interleaved for the same buffer.
--- Since attaches are asynchronous we need to make sure an attach isn't
--- performed whilst another one is in progress.
--- @param cbuf integer
--- @param ctx? Gitsigns.GitContext
--- @param aucmd? string
local attach_throttled = throttle_by_id(function(cbuf, ctx, aucmd)
  local __FUNC__ = 'attach'
  local passed_ctx = ctx ~= nil

  setup()

  if cache[cbuf] then
    dprint('Already attached')
    return
  end

  if aucmd then
    dprintf('Attaching (trigger=%s)', aucmd)
  else
    dprint('Attaching')
  end

  if not api.nvim_buf_is_loaded(cbuf) then
    dprint('Non-loaded buffer')
    return
  end

  if not ctx then
    local err
    ctx, err = get_buf_context(cbuf)
    if err then
      dprint(err)
      return
    end
    assert(ctx)
  end

  local encoding = vim.bo[cbuf].fileencoding
  if encoding == '' then
    encoding = 'utf-8'
  end

  local file = ctx.file
  if not vim.startswith(file, '/') and ctx.toplevel then
    file = ctx.toplevel .. util.path_sep .. file
  end

  local revision = ctx.base or config.base
  local git_obj = git.Obj.new(file, revision, encoding, ctx.gitdir, ctx.toplevel)

  if not git_obj and not passed_ctx then
    git_obj = try_worktrees(cbuf, file, revision, encoding)
    async.scheduler()
    if not api.nvim_buf_is_valid(cbuf) then
      return
    end
  end

  if not git_obj then
    dprint('Empty git obj')
    return
  end

  async.scheduler()
  if not api.nvim_buf_is_valid(cbuf) then
    return
  end

  Status:update(cbuf, {
    head = git_obj.repo.abbrev_head,
    root = git_obj.repo.toplevel,
    gitdir = git_obj.repo.gitdir,
  })

  if not passed_ctx and (not util.path_exists(file) or uv.fs_stat(file).type == 'directory') then
    dprint('Not a file')
    return
  end

  if not git_obj.relpath then
    dprint('Cannot resolve file in repo')
    return
  end

  if not config.attach_to_untracked and git_obj.object_name == nil then
    dprint('File is untracked')
    return
  end

  -- On windows os.tmpname() crashes in callback threads so initialise this
  -- variable on the main thread.
  async.scheduler()
  if not api.nvim_buf_is_valid(cbuf) then
    return
  end

  if config.on_attach and config.on_attach(cbuf) == false then
    dprint('User on_attach() returned false')
    return
  end

  cache[cbuf] = Cache.new({
    bufnr = cbuf,
    file = file,
    git_obj = git_obj,
  })

  if config.watch_gitdir.enable then
    cache[cbuf].deregister_watcher = git_obj.repo:register_callback(function()
      watcher_handler(cbuf)
    end)
  end

  if not api.nvim_buf_is_loaded(cbuf) then
    dprint('Un-loaded buffer')
    return
  end

  -- Make sure to attach before the first update (which is async) so we pick up
  -- changes from BufReadCmd.
  api.nvim_buf_attach(cbuf, false, {
    on_lines = on_lines,
    on_reload = on_reload,
    on_detach = on_detach,
  })

  api.nvim_create_autocmd('BufWrite', {
    group = 'gitsigns',
    buffer = cbuf,
    callback = function()
      manager.update_debounced(cbuf)
    end,
  })

  -- Initial update
  manager.update(cbuf)

  if config.current_line_blame then
    require('gitsigns.current_line_blame').update(cbuf)
  end
end)

--- Detach Gitsigns from all buffers it is attached to.
function M.detach_all()
  for k, _ in pairs(cache) do
    M.detach(k)
  end
end

--- Detach Gitsigns from the buffer {bufnr}. If {bufnr} is not
--- provided then the current buffer is used.
---
--- @param bufnr integer Buffer number
--- @param _keep_signs? boolean
function M.detach(bufnr, _keep_signs)
  -- When this is called interactively (with no arguments) we want to remove all
  -- the signs, however if called via a detach event (due to nvim_buf_attach)
  -- then we don't want to clear the signs in case the buffer is just being
  -- updated due to the file externally changing. When this happens a detach and
  -- attach event happen in sequence and so we keep the old signs to stop the
  -- sign column width moving about between updates.
  bufnr = bufnr or api.nvim_get_current_buf()
  dprint('Detached')
  local bcache = cache[bufnr]
  if not bcache then
    dprint('Cache was nil')
    return
  end

  manager.detach(bufnr, _keep_signs)

  -- Clear status variables
  Status:clear(bufnr)

  Cache.destroy(bufnr)
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
  attach_throttled(bufnr or api.nvim_get_current_buf(), ctx, _trigger)
end)

return M
