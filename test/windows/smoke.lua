local async = require('gitsigns.async')
local h = require('windows.harness')
local gs = require('windows.gitsigns')

--- @param fn function
--- @param name string
--- @return integer, any
local function find_upvalue(fn, name)
  local i = 1
  while true do
    local upname, value = debug.getupvalue(fn, i)
    if not upname then
      error(('missing upvalue: %s'):format(name), 2)
    end
    if upname == name then
      return i, value
    end
    i = i + 1
  end
end

--- @param fn function
--- @param replacements table<string, any>
--- @param cb fun()
local function with_upvalues(fn, replacements, cb)
  local original = {} --- @type {index: integer, value: any}[]

  for name, value in pairs(replacements) do
    local index, old_value = find_upvalue(fn, name)
    original[#original + 1] = { index = index, value = old_value }
    debug.setupvalue(fn, index, value)
  end

  local ok, err = xpcall(cb, debug.traceback)

  for i = #original, 1, -1 do
    local entry = original[i]
    debug.setupvalue(fn, entry.index, entry.value)
  end

  if not ok then
    error(err, 0)
  end
end

h.it('Repo.get_info normalizes mixed native and unix-style paths', function()
  if vim.fn.has('win32') ~= 1 then
    return
  end
  h.eq(1, vim.fn.executable('cygpath'), 'cygpath missing from PATH')

  local Repo = require('gitsigns.git.repo')

  gs.with_repo(function(repo)
    local native_root = repo.root
    local native_gitdir = repo.gitdir
    local unix_root = h.cygpath(native_root, 'unix')
    local unix_gitdir = h.cygpath(native_gitdir, 'unix')
    local expected_root = vim.fs.normalize(h.cygpath(native_root, 'mixed'))
    local expected_gitdir = vim.fs.normalize(h.cygpath(native_gitdir, 'mixed'))

    with_upvalues(Repo.get_info, {
      check_version = function()
        return true
      end,
      git_command = function()
        return { unix_root, unix_gitdir, 'main' }, nil, 0
      end,
    }, function()
      local info, err = async.run(Repo.get_info, native_root):wait(5000)
      h.eq(nil, err)
      h.ok(info ~= nil, 'expected repo info for mixed-style paths')
      h.eq(expected_root, info.toplevel)
      h.eq(expected_gitdir, info.gitdir)
      h.eq(false, info.detached)
    end)
  end)
end)

h.it('util.cygpath preserves native paths and converts unix paths', function()
  if vim.fn.has('win32') ~= 1 then
    return
  end
  h.eq(1, vim.fn.executable('cygpath'), 'cygpath missing from PATH')

  local util = require('gitsigns.util')

  gs.with_repo(function(repo)
    local native_root = repo.root
    local unix_root = h.cygpath(native_root, 'unix')
    local mixed_root = h.cygpath(native_root, 'mixed')
    local windows_root = h.cygpath(unix_root, 'windows')

    h.eq(native_root, async.run(util.cygpath, native_root, 'mixed'):wait(5000))
    h.eq(mixed_root, async.run(util.cygpath, unix_root, 'mixed'):wait(5000))
    h.eq(windows_root, async.run(util.cygpath, unix_root, 'windows'):wait(5000))
  end)
end)

h.it('Repo.get_info rejects native dirs outside a unix-style worktree', function()
  if vim.fn.has('win32') ~= 1 then
    return
  end
  h.eq(1, vim.fn.executable('cygpath'), 'cygpath missing from PATH')

  local Repo = require('gitsigns.git.repo')

  gs.with_repo(function(repo)
    local outside = h.tmpdir()
    local unix_root = h.cygpath(repo.root, 'unix')
    local unix_gitdir = h.cygpath(repo.gitdir, 'unix')

    local ok, err = pcall(function()
      with_upvalues(Repo.get_info, {
        check_version = function()
          return true
        end,
        git_command = function()
          return { unix_root, unix_gitdir, 'main' }, nil, 0
        end,
      }, function()
        local info = async.run(Repo.get_info, outside):wait(5000)
        h.eq(nil, info)
      end)
    end)
    h.cleanup(outside)
    if not ok then
      error(err, 0)
    end
  end)
end)

h.it('gitsigns attaches to a tracked file in a subdirectory', function()
  gs.with_repo(function(repo)
    h.edit(repo.file)

    local bufnr = vim.api.nvim_get_current_buf()
    local cache = gs.attach(bufnr, gs.context(repo))

    h.eq(repo.relpath, cache.git_obj.relpath)
    h.ok(cache.git_obj.object_name ~= nil, 'expected tracked file to have an object name')
    h.ok(cache.git_obj.repo.toplevel ~= nil, 'expected repo to have a toplevel')
  end, {
    relpath = 'sub/test.txt',
    lines = { 'hello', 'world' },
  })
end)

h.it('gitsigns attaches with a relative file path in the git context', function()
  gs.with_repo(function(repo)
    h.edit(repo.file)

    local bufnr = vim.api.nvim_get_current_buf()
    local cache = gs.attach(bufnr, gs.context(repo, repo.relpath))

    h.eq(repo.relpath, cache.git_obj.relpath)
    h.ok(cache.git_obj.object_name ~= nil, 'expected tracked file to have an object name')
  end, {
    relpath = 'sub/relative.txt',
    lines = { 'hello', 'world' },
  })
end)

h.it('gitsigns blames a tracked file in a nested path', function()
  gs.with_repo(function(repo)
    h.edit(repo.file)

    local bufnr = vim.api.nvim_get_current_buf()
    local cache = gs.attach(bufnr, gs.context(repo))

    h.eq(repo.relpath, cache.git_obj.relpath)
    h.ok(cache.git_obj.file ~= cache.git_obj.relpath, 'expected an absolute file path for blame')

    local blame_info = async
      .run(function()
        return cache:get_blame(1, {})
      end)
      :wait(5000)

    h.ok(blame_info ~= nil, 'expected blame info for first line')
    h.eq(repo.relpath, blame_info.filename)
    h.ok(blame_info.commit.sha ~= nil, 'expected committed blame info')
  end, {
    relpath = '.config/nvim/lua/mappings.lua',
    lines = { 'hello', 'world' },
  })
end)

h.it('gitsigns stages tracked changes after attach', function()
  gs.with_repo(function(repo)
    h.edit(repo.file)

    local bufnr = vim.api.nvim_get_current_buf()
    local cache = gs.attach(bufnr, gs.context(repo, repo.relpath))

    vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { 'changed' })
    cache:invalidate(true)
    cache = gs.update(bufnr)

    h.wait_for(function()
      return cache.hunks and #cache.hunks > 0
    end, {
      timeout = 5000,
      msg = 'expected gitsigns to detect buffer hunks',
    })

    gs.stage_hunks(bufnr)

    h.eq(
      repo.relpath,
      h.trim(h.system({ 'git', 'diff', '--cached', '--name-only' }, {
        cwd = repo.root,
      }).stdout)
    )
  end, {
    relpath = 'sub/stage.txt',
    lines = { 'hello', 'world' },
  })
end)
