local Status = require('gitsigns.status')
local async = require('gitsigns.async')
local git = require('gitsigns.git')
local Cache = require('gitsigns.cache')
local log = require('gitsigns.debug.log')
local manager = require('gitsigns.manager')
local Util = require('gitsigns.util')
local Path = Util.Path

local cache = Cache.cache
local config = require('gitsigns.config').config
local dprint = log.dprint
local dprintf = log.dprintf
local throttle_async = require('gitsigns.debounce').throttle_async

local api = vim.api
local uv = vim.uv or vim.loop ---@diagnostic disable-line: deprecated

--- @class gitsigns.attach
local M = {}

--- @param name string
--- @return string? rel_path
--- @return string? commit
--- @return string? gitdir
local function parse_git_path(name)
  if not vim.startswith(name, 'fugitive://') and not vim.startswith(name, 'gitsigns://') then
    return
  end

  local proto, gitdir, tail = unpack(vim.split(name, '//'))
  assert(proto and gitdir and tail)
  local plugin = proto:sub(1, 1):upper() .. proto:sub(2, -2)

  local commit, rel_path --- @type string?, string?
  if plugin == 'Gitsigns' then
    commit = tail:match('^(:?[^:]+):')
    rel_path = tail:match('^:?[^:]+:(.*)')
  else -- Fugitive
    commit = tail:match('^([^/]+)/')
    if commit and commit:match('^[0-3]$') then
      --- @diagnostic disable-next-line: no-unknown
      commit = ':' .. commit
    end
    rel_path = tail:match('^[^/]+/(.*)')
  end

  -- Fugitive worktree buffers do not have a path
  -- 'fugitive:///<gitdir>//<commit>/'
  if rel_path == '' then
    return
  end

  dprintf("%s buffer for file '%s' from path '%s' on commit '%s'", plugin, rel_path, name, commit)
  return rel_path, commit, gitdir
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
  assert(cache[bufnr]):invalidate()
  dprint('Reload')
  manager.update_sync_debounced(bufnr)
end

--- @param _ 'detach'
--- @param bufnr integer
local function on_detach(_, bufnr)
  api.nvim_clear_autocmds({ group = 'gitsigns', buffer = bufnr })
  M.detach(bufnr, true)
end

--- @async
--- @param bufnr integer
--- @return string?
--- @return string?
local function on_attach_pre(bufnr)
  --- @type string?, string?
  local gitdir, toplevel
  if config._on_attach_pre then
    --- @type {gitdir: string?, toplevel: string?}
    local res = async.await(2, config._on_attach_pre, bufnr)
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

local setup = Util.once(function()
  manager.setup()

  require('gitsigns.current_line_blame').setup()

  api.nvim_create_autocmd('BufFilePre', {
    group = 'gitsigns',
    desc = 'Gitsigns: detach when changing buffer names',
    callback = function(args)
      M.detach(args.buf)
    end,
  })

  api.nvim_create_autocmd('VimLeavePre', {
    desc = 'Gitsigns: detach from all buffers',
    group = 'gitsigns',
    callback = M.detach_all,
  })
end)

--- @class (exact) Gitsigns.GitContext
--- @field file string Path to the file represented by the buffer.
--- @field toplevel? string Path to the top-level of the parent git repository.
--- @field gitdir? string Path to the git directory of the parent git repository.
--- @field base? string Git revision to compare against.

--- @async
--- @param bufnr integer
--- @return Gitsigns.GitContext? ctx
--- @return string? err
local function get_buf_context(bufnr)
  if api.nvim_buf_line_count(bufnr) > config.max_file_length then
    return nil, 'Exceeds max_file_length'
  end

  local bufname = api.nvim_buf_get_name(bufnr)

  -- Resolve the buffer name to a real path (following symlinks) if we can,
  local bufpath = uv.fs_realpath(bufname) or bufname

  local rel_path, commit, gitdir_from_bufname = parse_git_path(bufpath)

  if not gitdir_from_bufname then
    if vim.bo[bufnr].buftype ~= '' then
      return nil, 'Non-normal buffer'
    elseif not Path.exists(vim.fs.dirname(bufpath)) then
      return nil, 'Not a path'
    elseif Path.is_dir(bufpath) then
      return nil, 'Not a file'
    end
  end

  local gitdir_oap, toplevel_oap = on_attach_pre(bufnr)

  return {
    file = rel_path or bufpath,
    gitdir = gitdir_oap or gitdir_from_bufname,
    toplevel = toplevel_oap,
    -- Stage buffers always compare against the common ancestor (':1')
    -- :0: index
    -- :1: common ancestor
    -- :2: target commit (HEAD)
    -- :3: commit which is being merged
    base = commit and (commit:match('^:[1-3]') and ':1' or commit) or nil,
  }
end

--- @async
--- @param bufnr integer
--- @param old_relpath? string
local function handle_moved(bufnr, old_relpath)
  local bcache = assert(cache[bufnr])
  local git_obj = bcache.git_obj

  local orig_relpath = assert(git_obj.orig_relpath or old_relpath)
  git_obj.orig_relpath = orig_relpath
  local new_name = git_obj.repo:diff_rename_status()[orig_relpath]
  if new_name then
    dprintf('File moved to %s', new_name)
    git_obj.relpath = new_name
    git_obj.file = git_obj.repo.toplevel .. '/' .. new_name
  elseif git_obj.orig_relpath then
    local orig_file = Path.join(git_obj.repo.toplevel, git_obj.orig_relpath)
    if not git_obj.repo:file_info(orig_file, git_obj.revision) then
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

  git_obj.file = Path.join(git_obj.repo.toplevel, git_obj.relpath)
  bcache.file = git_obj.file
  git_obj:refresh()
  if not bcache:schedule() then
    return
  end

  local bufexists = Util.bufexists(bcache.file)
  local old_name = api.nvim_buf_get_name(bufnr)

  if not bufexists then
    -- Do not trigger BufFilePre/Post
    -- TODO(lewis6991): figure out how to avoid reattaching without
    -- disabling all autocommands.
    Util.noautocmd({ 'BufFilePre', 'BufFilePost' }, function()
      Util.buf_rename(bufnr, bcache.file)
    end)
  end

  local msg = bufexists and 'Cannot rename' or 'Renamed'
  dprintf('%s buffer %d from %s to %s', msg, bufnr, old_name, bcache.file)
end

--- @async
--- @param bufnr integer
local function repo_update_handler(bufnr)
  local bcache = cache[bufnr]
  if not bcache then
    return
  end

  dprintf('Watcher handler called for buffer %d %s', bufnr, bcache.file)

  local git_obj = bcache.git_obj

  Status.update(bufnr, { head = git_obj.repo.abbrev_head })

  local was_tracked = git_obj.object_name ~= nil
  local old_relpath = git_obj.relpath

  bcache:invalidate(true)
  git_obj:refresh()
  if not bcache:schedule() then
    dprint('buffer invalid (1)')
    return
  end

  if config.watch_gitdir.follow_files and was_tracked and not git_obj.object_name then
    -- File was tracked but is no longer tracked. Must of been removed or
    -- moved. Check if it was moved and switch to it.
    handle_moved(bufnr, old_relpath)
    if not bcache:schedule() then
      dprint('buffer invalid (2)')
      return
    end
  end

  require('gitsigns.manager').update(bufnr)
end

--- @async
--- Ensure attaches cannot be interleaved for the same buffer.
--- Since attaches are asynchronous we need to make sure an attach isn't
--- performed whilst another one is in progress.
--- @param cbuf integer
--- @param ctx? Gitsigns.GitContext
--- @param aucmd? string
M.attach = throttle_async({ hash = 1 }, function(cbuf, ctx, aucmd)
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

  local file, toplevel = ctx.file, ctx.toplevel
  if not Path.is_abs(file) and toplevel then
    file = Path.join(toplevel, file)
  end

  local revision = ctx.base or config.base
  local git_obj = git.Obj.new(file, revision, encoding, ctx.gitdir, toplevel)

  if not git_obj and not passed_ctx then
    for _, wt in ipairs(config.worktrees) do
      git_obj = git.Obj.new(file, revision, encoding, wt.gitdir, wt.toplevel)
      if git_obj and git_obj.object_name then
        dprintf('Using worktree %s', vim.inspect(wt))
        break
      end
    end
  end

  if not git_obj then
    dprint('Empty git obj')
    return
  end

  async.schedule()
  if not api.nvim_buf_is_valid(cbuf) then
    return
  end

  Status.update(cbuf, {
    head = git_obj.repo.abbrev_head,
    root = git_obj.repo.toplevel,
    gitdir = git_obj.repo.gitdir,
  })

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
  async.schedule()
  if not api.nvim_buf_is_valid(cbuf) then
    return
  end

  if config.on_attach and config.on_attach(cbuf) == false then
    dprint('User on_attach() returned false')
    return
  end

  cache[cbuf] = Cache.new(cbuf, file, git_obj)

  if config.watch_gitdir.enable then
    dprintf('Watching git dir')

    --- Throttle to:
    --- - ensure handler is only triggered once per git operation.
    --- - prevent updates to the same buffer from interleaving as the handler is
    ---   async.
    local throttled_repo_update_handler = throttle_async({ schedule = true }, function()
      repo_update_handler(cbuf)
    end)

    cache[cbuf].deregister_watcher = git_obj.repo:on_update(function()
      async.run(throttled_repo_update_handler):raise_on_error()
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
      manager.update_sync_debounced(cbuf)
    end,
  })

  -- Initial update
  manager.update(cbuf)

  dprint('attach complete')

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
--- @param keep_signs? boolean
function M.detach(bufnr, keep_signs)
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

  manager.detach(bufnr, keep_signs)

  -- Clear status variables
  Status.clear(bufnr)

  Cache.destroy(bufnr)
end

return M
