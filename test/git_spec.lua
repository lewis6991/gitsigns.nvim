--- @diagnostic disable: access-invisible
local helpers = require('test.gs_helpers')

local clear = helpers.clear
local eq = helpers.eq
local eq_path = helpers.eq_path
local exec_lua = helpers.exec_lua
local fn = helpers.fn
local git = helpers.git
local mkdir = helpers.mkdir
local setup_test_repo = helpers.setup_test_repo
local write_to_file = helpers.write_to_file
local scratch --- @type string

helpers.env()

local function refresh_paths()
  scratch = helpers.scratch
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

describe('git', function()
  before_each(function()
    clear()
    refresh_paths()
    helpers.setup_path()
  end)

  it('serializes repo operations across objects in the same repo', function()
    local result = exec_lua(function()
      local async = require('gitsigns.async')
      local Obj = require('gitsigns.git').Obj
      local Repo = require('gitsigns.git.repo')

      return async
        .run(function()
          local entered = async.event()
          local release = async.event()
          local events = {} --- @type string[]

          local repo = setmetatable({
            _lock = async.semaphore(1),
          }, { __index = Repo })

          local obj_a = setmetatable({ repo = repo }, { __index = Obj })
          local obj_b = setmetatable({ repo = repo }, { __index = Obj })

          local task_a = async.run(function()
            obj_a:lock(function()
              events[#events + 1] = 'a_enter'
              entered:set()
              release:wait()
              events[#events + 1] = 'a_exit'
            end)
          end)

          local task_b = async.run(function()
            entered:wait()
            obj_b:lock(function()
              events[#events + 1] = 'b_enter'
              events[#events + 1] = 'b_exit'
            end)
          end)

          entered:wait()
          release:set()

          async.await(task_a)
          async.await(task_b)

          return {
            events = events,
          }
        end)
        :wait(5000)
    end)

    eq({ 'a_enter', 'a_exit', 'b_enter', 'b_exit' }, result.events)
  end)

  it('log_rename_status handles spaced filenames', function()
    helpers.git_init_scratch()

    local old_name = scratch .. '/old name.txt'
    local new_name = scratch .. '/new name.txt'

    write_to_file(old_name, { 'test' })
    git('add', old_name)
    git('commit', '-m', 'init commit')
    git('mv', old_name, new_name)
    git('commit', '-m', 'rename file')

    local old_relpath = exec_lua(function(repo_dir)
      local async = require('gitsigns.async')
      local Repo = require('gitsigns.git.repo')

      local repo = assert(async.run(Repo.get, repo_dir):wait(5000))
      local ret = async
        .run(function()
          return repo:log_rename_status('HEAD~1', 'new name.txt')
        end)
        :wait(5000)
      repo:unref()
      return ret
    end, scratch)

    eq('old name.txt', old_relpath)
  end)

  it('log_rename_status handles unicode filenames', function()
    helpers.git_init_scratch()

    local old_name = scratch .. '/föobær.txt'
    local new_name = scratch .. '/bår.txt'

    write_to_file(old_name, { 'test' })
    git('add', old_name)
    git('commit', '-m', 'init commit')
    git('mv', old_name, new_name)
    git('commit', '-m', 'rename file')

    local old_relpath = exec_lua(function(repo_dir)
      local async = require('gitsigns.async')
      local Repo = require('gitsigns.git.repo')

      local repo = assert(async.run(Repo.get, repo_dir):wait(5000))
      local ret = async
        .run(function()
          return repo:log_rename_status('HEAD~1', 'bår.txt')
        end)
        :wait(5000)
      repo:unref()
      return ret
    end, scratch)

    eq('föobær.txt', old_relpath)
  end)

  it('util.cygpath preserves native paths and converts unix paths', function()
    setup_test_repo()

    local supported = exec_lua(function()
      return vim.fn.has('win32') == 1 and vim.fn.executable('cygpath') == 1
    end)
    if not supported then
      return
    end

    local result = exec_lua(function(root)
      local async = require('gitsigns.async')
      local util = require('gitsigns.util')

      local unix_root = vim.trim(vim.fn.system({ 'cygpath', '--absolute', '--unix', root }))
      local mixed_root = vim.trim(vim.fn.system({ 'cygpath', '--absolute', '--mixed', root }))
      local windows_root =
        vim.trim(vim.fn.system({ 'cygpath', '--absolute', '--windows', unix_root }))

      return {
        native_mixed = async.run(util.cygpath, root, 'mixed'):wait(5000),
        unix_mixed = async.run(util.cygpath, unix_root, 'mixed'):wait(5000),
        unix_windows = async.run(util.cygpath, unix_root, 'windows'):wait(5000),
        expected_native = root,
        expected_mixed = mixed_root,
        expected_windows = windows_root,
      }
    end, scratch)

    eq(result.expected_native, result.native_mixed)
    eq(result.expected_mixed, result.unix_mixed)
    eq(result.expected_windows, result.unix_windows)
  end)

  it('infers submodule worktrees from gitdir metadata (#1513)', function()
    local superproject = scratch .. '/superproject'
    local submodule = scratch .. '/issue_submodule'
    local submodule_name = 'issue_submodule'

    init_repo(superproject)
    init_repo(submodule)

    write_to_file(superproject .. '/file', { 'superproject' })
    git_in(superproject, 'add', 'file')
    git_in(superproject, 'commit', '-m', 'superproject commit')

    write_to_file(submodule .. '/file', { 'submodule' })
    git_in(submodule, 'add', 'file')
    git_in(submodule, 'commit', '-m', 'submodule commit')

    git_in(
      superproject,
      '-c',
      'protocol.file.allow=always',
      'submodule',
      'add',
      submodule,
      submodule_name
    )

    local submodule_worktree = superproject .. '/' .. submodule_name
    local submodule_gitdir = superproject .. '/.git/modules/' .. submodule_name
    local commit_editmsg = submodule_gitdir .. '/COMMIT_EDITMSG'

    write_to_file(commit_editmsg, { '' }, { trailing_newline = false })

    local result = exec_lua(function(gitdir, file)
      local async = require('gitsigns.async')
      local Obj = require('gitsigns.git').Obj
      local Repo = require('gitsigns.git.repo')
      local config = require('gitsigns.config').config
      local log = require('gitsigns.debug.log')

      config.debug_mode = true

      local info = assert(async.run(Repo.get_info, nil, gitdir):wait(5000))

      log.clear()

      local old_gitdir = vim.env.GIT_DIR
      local old_worktree = vim.env.GIT_WORK_TREE
      vim.env.GIT_DIR = gitdir
      vim.env.GIT_WORK_TREE = nil

      local ok, obj_or_err = pcall(function()
        return async.run(Obj.new, file, nil, 'utf-8'):wait(5000)
      end)

      vim.env.GIT_DIR = old_gitdir
      vim.env.GIT_WORK_TREE = old_worktree

      local has_outside_worktree = false
      local has_outside_repo = false
      for _, line in ipairs(log.get(true) or {}) do
        if line:find('outside worktree', 1, true) then
          has_outside_worktree = true
        end
        if line:find('is outside repository at', 1, true) then
          has_outside_repo = true
        end
      end

      if ok and obj_or_err then
        obj_or_err:close()
      end

      return {
        ok = ok,
        err = ok and nil or obj_or_err,
        has_obj = ok and obj_or_err ~= nil,
        has_outside_worktree = has_outside_worktree,
        has_outside_repo = has_outside_repo,
        info = info,
      }
    end, submodule_gitdir, commit_editmsg)

    eq(true, result.ok, result.err)
    eq(false, result.has_obj)
    eq(false, result.has_outside_worktree)
    eq(false, result.has_outside_repo)
    eq_path(submodule_worktree, result.info.toplevel)
    eq_path(submodule_gitdir, result.info.gitdir)
  end)
end)
