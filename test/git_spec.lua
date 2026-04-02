--- @diagnostic disable: access-invisible
local helpers = require('test.gs_helpers')

local clear = helpers.clear
local eq = helpers.eq
local exec_lua = helpers.exec_lua
local git = helpers.git
local setup_test_repo = helpers.setup_test_repo
local write_to_file = helpers.write_to_file
local scratch --- @type string

helpers.env()

local function refresh_paths()
  scratch = helpers.scratch
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
      local uv = vim.uv or vim.loop ---@diagnostic disable-line: deprecated

      local sleep = async.wrap(2, function(timeout, cb)
        local timer = assert(uv.new_timer())
        timer:start(timeout, 0, cb)
        return timer
      end)

      _G._git_lock_events = {}

      local repo = setmetatable({
        _lock = async.semaphore(1),
      }, { __index = Repo })

      local obj_a = setmetatable({ repo = repo }, { __index = Obj })
      local obj_b = setmetatable({ repo = repo }, { __index = Obj })

      async
        .run(function()
          obj_a:lock(function()
            _G._git_lock_events[#_G._git_lock_events + 1] = 'a_enter'
            sleep(200)
            _G._git_lock_events[#_G._git_lock_events + 1] = 'a_exit'
          end)
        end)
        :raise_on_error()

      async
        .run(function()
          obj_b:lock(function()
            _G._git_lock_events[#_G._git_lock_events + 1] = 'b_enter'
            sleep(10)
            _G._git_lock_events[#_G._git_lock_events + 1] = 'b_exit'
          end)
        end)
        :raise_on_error()

      vim.wait(1000, function()
        return #_G._git_lock_events == 4
      end, 10, true)

      return {
        events = _G._git_lock_events,
      }
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
end)
