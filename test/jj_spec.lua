local helpers = require('test.gs_helpers')

local clear = helpers.clear
local eq = helpers.eq
local eq_path = helpers.eq_path
local exec_lua = helpers.exec_lua
local fn = helpers.fn
local mkdir = helpers.mkdir
local write_to_file = helpers.write_to_file
local uv = vim.uv or vim.loop ---@diagnostic disable-line: deprecated
local tmpdir --- @type string

helpers.env()

-- Join path segments with '/' and normalize.
--- @param ... string
--- @return string
local function join(...)
  return (vim.fs.normalize(table.concat({ ... }, '/')))
end

-- Need to use tmpdir instead of scratch to avoid confusion with the actual git
-- repo present. This allows us to test the jj path.
local function refresh_paths()
  tmpdir = join(uv.os_tmpdir() or '/tmp', 'jj-test-' .. tostring(uv.hrtime()))
  mkdir(tmpdir)
  -- On Windows, os_tmpdir() can return a short (8.3) path alias (e.g.
  -- `RUNNER~1` on GitHub Actions runners) that doesn't string-match the
  -- long-form paths git and the OS report elsewhere. Canonicalize once here
  -- so every path built from `tmpdir` agrees with what git returns.
  tmpdir = join(uv.fs_realpath(tmpdir) or tmpdir)
end

local function cleanup_tmpdir()
  if tmpdir then
    fn.delete(tmpdir, 'rf')
  end
end

--- @param cmd string[]
--- @param errmsg string
local function system_ok(cmd, errmsg)
  local output = fn.system(cmd)
  eq(0, exec_lua('return vim.v.shell_error'), ('%s\n%s'):format(errmsg, output))
end

--- @param path string
local function git_in(path, ...)
  system_ok(
    vim.list_extend({ 'git', '-C', path }, { ... }),
    ('git command failed in %s'):format(path)
  )
end

--- @param path string
local function init_repo(path)
  mkdir(path)
  git_in(path, 'init', '-b', 'main')
  git_in(path, 'config', 'user.email', 'tester@com.com')
  git_in(path, 'config', 'user.name', 'tester')
end

describe('jj', function()
  before_each(function()
    clear()
    refresh_paths()
    helpers.setup_path()
  end)

  after_each(function()
    cleanup_tmpdir()
  end)

  it('resolves gitdir for an uncolocated jj repo', function()
    local backing = join(tmpdir, 'uncolocated-backing')
    local workspace = join(tmpdir, 'uncolocated')
    local backing_gitdir = join(backing, '.git')

    -- Create backing git repo with an initial commit
    init_repo(backing)
    write_to_file(join(backing, 'file.txt'), { 'test content' })
    git_in(backing, 'add', 'file.txt')
    git_in(backing, 'commit', '-m', 'init commit')

    -- Create workspace with jj structure pointing to backing repo
    mkdir(workspace)
    write_to_file(join(workspace, '.jj', 'repo', 'store', 'git_target'), { backing_gitdir })

    local result = exec_lua(function(dir)
      local async = require('gitsigns.async')
      local Repo = require('gitsigns.git.repo')

      -- Discover from workspace directory
      local info = async.run(Repo.get_info, dir):wait(5000)
      return info
    end, workspace)

    assert(result, 'get_info should succeed for uncolocated jj repo')
    eq_path(backing_gitdir, result.gitdir)
    eq_path(workspace, result.toplevel)
    eq(true, result.detached)
    eq(nil, result.abbrev_head)
  end)

  it('resolves a secondary jj workspace to its own toplevel', function()
    local backing = join(tmpdir, 'workspace-backing')
    local primary = join(tmpdir, 'workspace-primary')
    local secondary = join(tmpdir, 'workspace-secondary')
    local backing_gitdir = join(backing, '.git')
    local primary_jj_repo = join(primary, '.jj', 'repo')

    -- Create backing git repo
    init_repo(backing)
    write_to_file(join(backing, 'file.txt'), { 'test content' })
    git_in(backing, 'add', 'file.txt')
    git_in(backing, 'commit', '-m', 'init commit')

    -- Create primary workspace pointing to backing repo
    mkdir(primary)
    write_to_file(join(primary_jj_repo, 'store', 'git_target'), { backing_gitdir })

    -- Create secondary workspace with nested subdir, .jj/repo as a file
    -- pointing to primary's .jj/repo directory
    local nested_dir = join(secondary, 'nested', 'buffer', 'dir')
    mkdir(nested_dir)
    write_to_file(join(secondary, '.jj', 'repo'), { primary_jj_repo })

    local result = exec_lua(function(dir)
      local async = require('gitsigns.async')
      local Repo = require('gitsigns.git.repo')

      -- Discover from nested dir inside secondary workspace
      local info = async.run(Repo.get_info, dir):wait(5000)
      return info
    end, nested_dir)

    assert(result, 'get_info should succeed for secondary jj workspace')
    eq_path(backing_gitdir, result.gitdir)
    -- CRITICAL ASSERTION (D3): toplevel should be secondary, NOT primary
    eq_path(secondary, result.toplevel)
    eq(nil, result.abbrev_head)
  end)

  it('ignores a broken .jj when .git is already present (colocated)', function()
    local repo = join(tmpdir, 'colocated')
    local repo_gitdir = join(repo, '.git')
    -- Absolute, but guaranteed not to exist on any platform: a path nested
    -- under tmpdir that we never create.
    local dangling_gitdir = join(tmpdir, 'nonexistent-backing', '.git')

    -- Create a normal git repo
    init_repo(repo)
    write_to_file(join(repo, 'file.txt'), { 'test content' })
    git_in(repo, 'add', 'file.txt')
    git_in(repo, 'commit', '-m', 'init commit')

    -- Add a deliberately broken .jj structure to test that native discovery
    -- takes priority (D1 — regression guard)
    write_to_file(join(repo, '.jj', 'repo', 'store', 'git_target'), { dangling_gitdir })

    local result = exec_lua(function(dir)
      local async = require('gitsigns.async')
      local Repo = require('gitsigns.git.repo')

      local info = async.run(Repo.get_info, dir):wait(5000)
      return info
    end, repo)

    assert(result, 'get_info should succeed (native discovery, not jj)')
    eq_path(repo_gitdir, result.gitdir)
    eq_path(repo, result.toplevel)
    eq(false, result.detached)
    -- native discovery succeeds, so abbrev_head is non-nil (the actual branch name)
    assert(
      result.abbrev_head ~= nil,
      'abbrev_head should be non-nil when native discovery succeeds'
    )
  end)

  describe('jj.resolve graceful failure', function()
    it('returns nil when no .jj directory exists', function()
      local dir = join(tmpdir, 'no-jj')
      mkdir(dir)

      local result = exec_lua(function(d)
        return { require('gitsigns.jj.detect').resolve(d) }
      end, dir)

      eq(nil, result[1])
      eq(nil, result[2])
    end)

    it('returns nil when .jj/repo is a directory but store/git_target is missing', function()
      local dir = join(tmpdir, 'missing-git-target')
      mkdir(dir)
      -- Create .jj/repo directory but don't create store/git_target
      mkdir(join(dir, '.jj', 'repo'))

      local result = exec_lua(function(d)
        return { require('gitsigns.jj.detect').resolve(d) }
      end, dir)

      eq(nil, result[1])
      eq(nil, result[2])
    end)

    it('returns nil when .jj/repo is a file pointing to nonexistent directory', function()
      local dir = join(tmpdir, 'dangling-workspace')
      mkdir(dir)
      -- Create .jj/repo as a file pointing to a nonexistent location
      write_to_file(join(dir, '.jj', 'repo'), { join(tmpdir, 'nonexistent-repo', 'dir') })

      local result = exec_lua(function(d)
        return { require('gitsigns.jj.detect').resolve(d) }
      end, dir)

      eq(nil, result[1])
      eq(nil, result[2])
    end)

    it('returns nil when store/git_target points to nonexistent path', function()
      local dir = join(tmpdir, 'dangling-git-target')
      mkdir(dir)
      -- Create .jj/repo directory with git_target pointing to nonexistent git store
      write_to_file(
        join(dir, '.jj', 'repo', 'store', 'git_target'),
        { join(tmpdir, 'nonexistent-target', '.git') }
      )

      local result = exec_lua(function(d)
        return { require('gitsigns.jj.detect').resolve(d) }
      end, dir)

      eq(nil, result[1])
      eq(nil, result[2])
    end)

    it(
      'does not cross into an unrelated outer .jj when dir is inside a nested repo .git',
      function()
        -- Regression test: an outer directory has a .jj (as if the whole tree
        -- were itself a jj-colocated repo), but `dir` is inside a *different*,
        -- inner git repo's own .git directory. The walk must stop at that
        -- inner .git boundary and never misattribute the file to the outer
        -- .jj, even though one exists further up.
        local outer = join(tmpdir, 'outer')
        mkdir(join(outer, '.jj', 'repo'))
        write_to_file(
          join(outer, '.jj', 'repo', 'store', 'git_target'),
          { join(tmpdir, 'should-never-be-used', '.git') }
        )

        local inner = join(outer, 'inner-repo')
        init_repo(inner)

        local result = exec_lua(function(d)
          return { require('gitsigns.jj.detect').resolve(d) }
        end, join(inner, '.git'))

        eq(nil, result[1])
        eq(nil, result[2])
      end
    )
  end)
end)
