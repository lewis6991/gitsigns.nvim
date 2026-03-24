--- @diagnostic disable: access-invisible
local helpers = require('test.gs_helpers')

local clear = helpers.clear
local eq = helpers.eq
local exec_lua = helpers.exec_lua
local git = helpers.git
local scratch = helpers.scratch
local write_to_file = helpers.write_to_file

helpers.env()

describe('git', function()
  before_each(function()
    clear()
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
            sleep(2500)
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

      vim.wait(4000, function()
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
      return async
        .run(function()
          return repo:log_rename_status('HEAD~1', 'new name.txt')
        end)
        :wait(5000)
    end, scratch)

    eq('old name.txt', old_relpath)
  end)
end)
