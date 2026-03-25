local H = require('windows.harness')
local async = require('gitsigns.async')

local M = {}

local initialized = false

local function pack_len(...)
  return { n = select('#', ...), ... }
end

local function unpack_len(t, first)
  return unpack(t, first or 1, t.n or table.maxn(t))
end

function M.setup()
  if initialized then
    return
  end

  require('gitsigns').setup({
    _test_mode = true,
    attach_to_untracked = true,
    auto_attach = false,
    debug_mode = true,
    update_debounce = 5,
  })

  H.after_each(function()
    pcall(function()
      require('gitsigns').detach_all()
    end)

    vim.env.GIT_DIR = nil
    vim.env.GIT_WORK_TREE = nil
  end)

  initialized = true
end

function M.setup_repo(opts)
  opts = opts or {}

  local root = H.tmpdir()
  local gitdir = H.join(root, '.git')
  local relpath = opts.relpath or 'test.txt'
  local file = H.join(root, relpath)

  H.system({ 'git', 'init', '-b', 'main' }, { cwd = root })
  H.system({ 'git', 'config', 'user.email', 'tester@example.com' }, { cwd = root })
  H.system({ 'git', 'config', 'user.name', 'tester' }, { cwd = root })

  H.write_file(file, opts.lines or { 'hello', 'world' })

  H.system({ 'git', 'add', relpath }, { cwd = root })
  H.system({ 'git', 'commit', '-m', 'init' }, { cwd = root })

  return {
    file = file,
    gitdir = gitdir,
    relpath = relpath,
    root = root,
  }
end

function M.with_repo(fn, opts)
  local repo = M.setup_repo(opts)
  local result --- @type any[]?
  local ok, err = xpcall(function()
    result = pack_len(fn(repo))
  end, debug.traceback)
  H.cleanup(repo.root)
  if not ok then
    error(err, 0)
  end
  return unpack_len(result or { n = 0 })
end

function M.wait_for_attach(bufnr, timeout)
  H.wait_for(function()
    return require('gitsigns.cache').cache[bufnr] ~= nil
  end, {
    timeout = timeout or 5000,
    msg = ('gitsigns did not attach to buffer %d'):format(bufnr),
  })
  return require('gitsigns.cache').cache[bufnr]
end

--- @param repo {file: string, gitdir: string, relpath: string, root: string}
--- @param file? string
--- @return Gitsigns.GitContext
function M.context(repo, file)
  return {
    file = file or repo.file,
    gitdir = repo.gitdir,
    toplevel = repo.root,
  }
end

--- @param bufnr integer
--- @param ctx? Gitsigns.GitContext
function M.attach(bufnr, ctx)
  async.run(require('gitsigns.attach').attach, bufnr, ctx, 'windows-smoke'):wait(5000)

  return M.wait_for_attach(bufnr, 5000)
end

--- @param bufnr integer
--- @return Gitsigns.CacheEntry
function M.update(bufnr)
  async.run(require('gitsigns.manager').update, bufnr):wait(5000)
  return assert(require('gitsigns.cache').cache[bufnr])
end

--- @param bufnr integer
--- @return Gitsigns.CacheEntry
function M.stage_hunks(bufnr)
  local cache = assert(require('gitsigns.cache').cache[bufnr])
  local Path = require('gitsigns.util').Path

  if not Path.exists(cache.git_obj.file) then
    error(('expected git_obj.file to exist: %s'):format(cache.git_obj.file), 2)
  end

  async
    .run(function()
      cache.git_obj:lock(function()
        local hunks = cache.hunks
        assert(hunks and #hunks > 0, 'expected hunks to stage')
        local err = cache.git_obj:stage_hunks(hunks)
        if err then
          error(err)
        end
      end)
    end)
    :wait(5000)

  return cache
end

return M
