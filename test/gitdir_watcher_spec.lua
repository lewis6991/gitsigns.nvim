--- @diagnostic disable: access-invisible
local helpers = require('test.gs_helpers')

local clear = helpers.clear
local system = helpers.fn.system
local edit = helpers.edit
local eq = helpers.eq
local setup_test_repo = helpers.setup_test_repo
local cleanup = helpers.cleanup
local command = helpers.api.nvim_command
local test_config = helpers.test_config
local match_debug_messages = helpers.match_debug_messages
local n, p, np = helpers.n, helpers.p, helpers.np
local normalize_path = helpers.normalize_path
local path_pattern = helpers.path_pattern
local setup_gitsigns = helpers.setup_gitsigns
local test_file = helpers.test_file
local git = helpers.git

helpers.env()

local function get_bufs()
  local bufs = {} --- @type table<integer,string>
  for _, b in ipairs(helpers.api.nvim_list_bufs()) do
    bufs[b] = normalize_path(helpers.api.nvim_buf_get_name(b))
  end
  return bufs
end

--- @param expected table<integer, string>
local function eq_bufs(expected)
  local normalized = {} --- @type table<integer, string?>
  for bufnr, path in pairs(expected) do
    normalized[bufnr] = normalize_path(path)
  end
  eq(normalized, get_bufs())
end

describe('gitdir_watcher', function()
  before_each(function()
    clear()
    helpers.chdir_tmp()
  end)

  after_each(function()
    cleanup()
  end)

  it('can follow moved files', function()
    setup_test_repo()
    setup_gitsigns(test_config)
    command('Gitsigns clear_debug')
    edit(test_file)

    local revparse_pat = ('system.system: git .* rev-parse --show-toplevel --absolute-git-dir --abbrev-ref HEAD'):gsub(
      '%-',
      '%%-'
    )

    match_debug_messages({
      'attach.attach(1): Attaching (trigger=BufReadPost)',
      np(revparse_pat),
      np('system.system: git .* config user.name'),
      np('system.system: git .* ls%-files .* ' .. path_pattern(test_file)),
      np('attach%.attach%(1%): Watching git dir .*'),
      np('system.system: git .* show .*'),
    })

    eq_bufs({ [1] = test_file })

    command('Gitsigns clear_debug')

    local test_file2 = test_file .. '2'
    git('mv', test_file, test_file2)

    match_debug_messages({
      p('git.repo.watcher.watcher.handler: Git dir update: .*'),
      np('system.system: git .* ls%-files .* ' .. path_pattern(test_file)),
      np('system.system: git .* diff %-%-name%-status .* %-%-cached'),
      n('attach.handle_moved(1): File moved to dummy.txt2'),
      np('system.system: git .* ls%-files .* ' .. path_pattern(test_file2)),
      np(
        'attach%.handle_moved%(1%): Renamed buffer 1 from '
          .. path_pattern(test_file)
          .. ' to '
          .. path_pattern(test_file2)
      ),
      np('system.system: git .* show .*'),
    })

    eq_bufs({ [1] = test_file2 })

    command('Gitsigns clear_debug')

    local test_file3 = test_file .. '3'

    git('mv', test_file2, test_file3)

    match_debug_messages({
      p('git.repo.watcher.watcher.handler: Git dir update: .*'),
      np('system.system: git .* ls%-files .* ' .. path_pattern(test_file2)),
      np('system.system: git .* diff %-%-name%-status .* %-%-cached'),
      n('attach.handle_moved(1): File moved to dummy.txt3'),
      np('system.system: git .* ls%-files .* ' .. path_pattern(test_file3)),
      np(
        'attach%.handle_moved%(1%): Renamed buffer 1 from '
          .. path_pattern(test_file2)
          .. ' to '
          .. path_pattern(test_file3)
      ),
      np('system.system: git .* show .*'),
    })

    eq_bufs({ [1] = test_file3 })

    command('Gitsigns clear_debug')

    git('mv', test_file3, test_file)

    match_debug_messages({
      p('git.repo.watcher.watcher.handler: Git dir update: .*'),
      np('system.system: git .* ls%-files .* ' .. path_pattern(test_file3)),
      np('system.system: git .* diff %-%-name%-status .* %-%-cached'),
      np('system.system: git .* ls%-files .* ' .. path_pattern(test_file)),
      n('attach.handle_moved(1): Moved file reset'),
      np('system.system: git .* ls%-files .* ' .. path_pattern(test_file)),
      np(
        'attach%.handle_moved%(1%): Renamed buffer 1 from '
          .. path_pattern(test_file3)
          .. ' to '
          .. path_pattern(test_file)
      ),
      np('system.system: git .* show .*'),
    })

    eq_bufs({ [1] = test_file })
  end)

  it('can follow moved files with spaces', function()
    helpers.git_init_scratch()

    local test_file1 = helpers.scratch .. '/old name.txt'
    local test_file2 = helpers.scratch .. '/new name.txt'

    helpers.write_to_file(test_file1, { 'test' })
    git('add', test_file1)
    git('commit', '-m', 'init commit')

    setup_gitsigns(test_config)
    edit(test_file1)

    helpers.expectf(function()
      return helpers.exec_lua(function()
        return vim.b.gitsigns_status_dict.gitdir ~= nil
      end)
    end)

    git('mv', test_file1, test_file2)

    helpers.expectf(function()
      eq_bufs({ [1] = test_file2 })
    end)
  end)

  it('preserves slash branch names on head updates', function()
    setup_test_repo()
    setup_gitsigns(test_config)
    edit(test_file)

    helpers.expectf(function()
      return helpers.exec_lua(function()
        return vim.b.gitsigns_status_dict.gitdir ~= nil
      end)
    end)

    helpers.check({ status = { head = 'main', added = 0, changed = 0, removed = 0 } })

    git('checkout', '-B', 'feature/foo')

    helpers.check({ status = { head = 'feature/foo', added = 0, changed = 0, removed = 0 } })
  end)

  it('can debounce and throttle updates per buffer', function()
    helpers.git_init_scratch()

    local f1 = vim.fs.joinpath(helpers.scratch, 'file1')
    local f2 = vim.fs.joinpath(helpers.scratch, 'file2')

    helpers.write_to_file(f1, { '1', '2', '3' })
    helpers.write_to_file(f2, { '1', '2', '3' })

    git('add', f1, f2)
    git('commit', '-m', 'init commit')

    setup_gitsigns(test_config)

    command('edit ' .. f1)
    helpers.feed('Aa<esc>')
    command('write')
    local b1 = helpers.api.nvim_get_current_buf()

    command('split ' .. f2)
    helpers.feed('Ab<esc>')
    command('write')
    local b2 = helpers.api.nvim_get_current_buf()

    helpers.check({ signs = { changed = 1 } }, b1)
    helpers.check({ signs = { changed = 1 } }, b2)

    git('add', f1, f2)

    helpers.check({ signs = {} }, b1)
    helpers.check({ signs = {} }, b2)
  end)

  it('gc proxy closes over handles without retaining watcher', function()
    setup_test_repo()
    helpers.setup_path()

    local result = helpers.exec_lua(function(scratch)
      local async = require('gitsigns.async')
      local Repo = require('gitsigns.git.repo')

      local repo, err = async.run(Repo.get, scratch):wait(5000)
      assert(repo, err)

      local watcher = repo._watcher
      local gc = assert(getmetatable(watcher._gc).__gc)
      local captured = {
        handles = false,
        watcher = false,
      }

      for i = 1, 20 do
        local name, value = debug.getupvalue(gc, i)
        if not name then
          break
        end
        if value == watcher.handles then
          captured.handles = true
        end
        if value == watcher then
          captured.watcher = true
        end
      end

      return captured
    end, helpers.scratch)

    eq(true, result.handles)
    eq(false, result.watcher)
  end)

  it('garbage collects repo and watcher', function()
    setup_test_repo()
    helpers.setup_path()

    local result = helpers.exec_lua(function(scratch)
      local async = require('gitsigns.async')
      local Repo = require('gitsigns.git.repo')

      local repo, err = async.run(Repo.get, scratch):wait(5000)
      assert(repo, err)

      local gitdir = repo.gitdir
      local watcher = repo._watcher
      local handles = {} --- @type uv.uv_fs_event_t[]
      -- `watcher.handles` is a map from watched dir -> handle. Copy into a
      -- list so we can assert every handle is closed after GC.
      for _, handle in pairs(watcher.handles) do
        handles[#handles + 1] = handle
      end
      assert(#handles > 0)

      local function get_upvalue(fn, key)
        for i = 1, 50 do
          local name, value = debug.getupvalue(fn, i)
          if not name then
            break
          end
          if name == key then
            return value
          end
        end
      end

      local repo_cache = get_upvalue(Repo.get, 'repo_cache')
      assert(repo_cache, 'repo_cache not found')

      local weak = setmetatable({ repo, watcher }, { __mode = 'v' })

      --- @diagnostic disable-next-line: unused, assign-type-mismatch
      --- assign to nil to allow gc
      watcher, repo = nil, nil

      vim.wait(2000, function()
        collectgarbage('collect')

        local handles_closed = true
        for _, handle in ipairs(handles) do
          handles_closed = handles_closed and handle:is_closing()
        end

        return weak[1] == nil and weak[2] == nil and repo_cache[gitdir] == nil and handles_closed
      end, 20, false)

      return {
        repo_gced = weak[1] == nil,
        watcher_gced = weak[2] == nil,
        cache_cleared = repo_cache[gitdir] == nil,
        handle_closed = (function()
          local closed = true
          for _, handle in ipairs(handles) do
            closed = closed and handle:is_closing()
          end
          return closed
        end)(),
      }
    end, helpers.scratch)

    eq(true, result.repo_gced)
    eq(true, result.watcher_gced)
    eq(true, result.cache_cleared)
    eq(true, result.handle_closed)
  end)
end)
