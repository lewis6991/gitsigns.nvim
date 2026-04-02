--- @diagnostic disable: access-invisible
local helpers = require('test.gs_helpers')

local clear = helpers.clear
local system = helpers.fn.system
local edit = helpers.edit
local eq = helpers.eq
local setup_test_repo = helpers.setup_test_repo
local cleanup = helpers.cleanup
local command = helpers.api.nvim_command
local match_dag = helpers.match_dag
local test_config = helpers.test_config
local match_debug_messages = helpers.match_debug_messages
local n, p, np = helpers.n, helpers.p, helpers.np
local normalize_path = helpers.normalize_path
local path_pattern = helpers.path_pattern
local setup_gitsigns = helpers.setup_gitsigns
local git = helpers.git
local test_file --- @type string

helpers.env()

local function refresh_paths()
  test_file = helpers.test_file
end

local watcher_test_config = vim.tbl_deep_extend('force', vim.deepcopy(test_config), {
  watch_gitdir = {
    enable = true,
  },
})

local watcher_fallback_test_config =
  vim.tbl_deep_extend('force', vim.deepcopy(watcher_test_config), {
    _allow_fs_poll_fallback = true,
  })

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

--- @param with_poll? boolean
local function install_failing_fs_watchers(with_poll)
  helpers.exec_lua(function(with_poll0)
    local uv = vim.uv or vim.loop

    local function new_fake_handle(fields)
      local handle = fields or {}
      handle._closed = false

      function handle:stop() end

      function handle:close()
        self._closed = true
      end

      function handle:is_closing()
        return self._closed
      end

      return handle
    end

    uv.new_fs_event = function()
      local handle = new_fake_handle()

      function handle:start(_, _, cb)
        vim.schedule(function()
          if not self._closed then
            cb('EMFILE', nil, nil)
          end
        end)
        return 0
      end

      return handle
    end

    if not with_poll0 then
      return
    end

    local poll_id = 0

    uv.new_fs_poll = function()
      poll_id = poll_id + 1

      local handle = new_fake_handle({ _id = poll_id })

      function handle:start(path, _, cb)
        self._path = path
        self._cb = cb
        return 0
      end

      return handle
    end
  end, with_poll)
end

describe('gitdir_watcher', function()
  before_each(function()
    clear()
    refresh_paths()
    helpers.chdir_tmp()
  end)

  after_each(function()
    cleanup()
  end)

  it('can follow moved files', function()
    setup_test_repo()
    setup_gitsigns(watcher_test_config)
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

    match_dag({
      p('system.system: git .* diff %-%-name%-status .* %-%-cached'),
      p('attach.handle_moved%(1%): File moved to dummy%.txt2'),
      p('system.system: git .* ls%-files .* ' .. path_pattern(test_file2) .. '$'),
      p(
        'attach%.handle_moved%(1%): Renamed buffer 1 from '
          .. path_pattern(test_file)
          .. ' to '
          .. path_pattern(test_file2)
      ),
      p('system.system: git .* show .*'),
    })

    eq_bufs({ [1] = test_file2 })

    command('Gitsigns clear_debug')

    local test_file3 = test_file .. '3'

    git('mv', test_file2, test_file3)

    match_dag({
      p('system.system: git .* diff %-%-name%-status .* %-%-cached'),
      p('attach.handle_moved%(1%): File moved to dummy%.txt3'),
      p('system.system: git .* ls%-files .* ' .. path_pattern(test_file3) .. '$'),
      p(
        'attach%.handle_moved%(1%): Renamed buffer 1 from '
          .. path_pattern(test_file2)
          .. ' to '
          .. path_pattern(test_file3)
      ),
      p('system.system: git .* show .*'),
    })

    eq_bufs({ [1] = test_file3 })

    command('Gitsigns clear_debug')

    git('mv', test_file3, test_file)

    match_dag({
      p('system.system: git .* diff %-%-name%-status .* %-%-cached'),
      p('attach.handle_moved%(1%): Moved file reset'),
      p('system.system: git .* ls%-files .* ' .. path_pattern(test_file) .. '$'),
      p(
        'attach%.handle_moved%(1%): Renamed buffer 1 from '
          .. path_pattern(test_file3)
          .. ' to '
          .. path_pattern(test_file)
      ),
      p('system.system: git .* show .*'),
    })

    eq_bufs({ [1] = test_file })
  end)

  it('does not delete alternate buffers when following moved files', function()
    setup_test_repo()
    setup_gitsigns(watcher_test_config)
    edit(test_file)
    local tracked_buf = helpers.api.nvim_get_current_buf()

    helpers.expectf(function()
      return helpers.exec_lua(function()
        return vim.b.gitsigns_status_dict ~= nil
      end)
    end)

    local alt_file = helpers.scratch .. '/alt.txt'
    helpers.write_to_file(alt_file, { 'alt buffer' })
    edit(alt_file)
    local alt_buf = helpers.api.nvim_get_current_buf()

    command('buffer ' .. tracked_buf)

    local test_file2 = test_file .. '2'
    git('mv', test_file, test_file2)

    helpers.expectf(function()
      eq_bufs({
        [tracked_buf] = test_file2,
        [alt_buf] = alt_file,
      })
    end)
  end)

  it('can follow moved files with spaces', function()
    helpers.git_init_scratch()

    local test_file1 = helpers.scratch .. '/old name.txt'
    local test_file2 = helpers.scratch .. '/new name.txt'

    helpers.write_to_file(test_file1, { 'test' })
    git('add', test_file1)
    git('commit', '-m', 'init commit')

    setup_gitsigns(watcher_test_config)
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
    setup_gitsigns(watcher_test_config)
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

    setup_gitsigns(watcher_test_config)

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

  it('falls back to fs_poll when fs_event fails', function()
    setup_test_repo({ no_add = true })
    install_failing_fs_watchers()

    setup_gitsigns(watcher_fallback_test_config)
    edit(test_file)

    helpers.expectf(function()
      return helpers.exec_lua(function()
        local bcache = require('gitsigns.cache').cache[vim.api.nvim_get_current_buf()]
        return bcache ~= nil
          and bcache.git_obj.repo._watcher ~= nil
          and bcache.git_obj.repo._watcher._backend == 'fs_poll'
          and vim.b.gitsigns_status_dict.gitdir ~= nil
      end)
    end)

    git('add', test_file)

    helpers.check({ status = { head = '', added = 0, changed = 0, removed = 0 }, signs = {} })
  end)

  it('recreates fs_poll watches after poll errors', function()
    setup_test_repo({ no_add = true })
    install_failing_fs_watchers(true)

    setup_gitsigns(watcher_fallback_test_config)
    edit(test_file)

    helpers.expectf(function()
      return helpers.exec_lua(function()
        local bcache = require('gitsigns.cache').cache[vim.api.nvim_get_current_buf()]
        return bcache ~= nil
          and bcache.git_obj.repo._watcher ~= nil
          and bcache.git_obj.repo._watcher._backend == 'fs_poll'
      end)
    end)

    eq(
      true,
      helpers.exec_lua(function()
        local bcache = require('gitsigns.cache').cache[vim.api.nvim_get_current_buf()]
        local repo = assert(bcache).git_obj.repo
        local watcher = assert(repo._watcher)
        local watched_path, old = next(watcher.handles)
        assert(watched_path and old)

        old._cb('ENOENT', nil, nil)

        local new = assert(watcher.handles[watched_path])
        return old:is_closing() and new ~= old and not new:is_closing()
      end)
    )

    git('add', test_file)

    helpers.exec_lua(function()
      local bcache = require('gitsigns.cache').cache[vim.api.nvim_get_current_buf()]
      local repo = assert(bcache).git_obj.repo
      local _, handle = next(assert(repo._watcher).handles)
      assert(handle)
      handle._cb(nil, nil, nil)
    end)

    helpers.check({ status = { head = '', added = 0, changed = 0, removed = 0 }, signs = {} })
  end)

  it('closes and recreates watchers when buffers detach and reattach', function()
    setup_test_repo()
    setup_gitsigns(watcher_test_config)
    edit(test_file)

    helpers.expectf(function()
      return helpers.exec_lua(function()
        local bcache = require('gitsigns.cache').cache[vim.api.nvim_get_current_buf()]
        return bcache ~= nil and bcache.git_obj.repo._watcher ~= nil
      end)
    end)

    local handle_count = helpers.exec_lua(function()
      local bcache = require('gitsigns.cache').cache[vim.api.nvim_get_current_buf()]
      local repo = assert(bcache).git_obj.repo

      _G.gitsigns_test_repo = repo
      _G.gitsigns_test_watcher_handles = {}

      for _, handle in pairs(assert(repo._watcher).handles) do
        _G.gitsigns_test_watcher_handles[#_G.gitsigns_test_watcher_handles + 1] = handle
      end

      return #_G.gitsigns_test_watcher_handles
    end)

    eq(true, handle_count > 0)

    command('Gitsigns detach')

    helpers.expectf(function()
      return helpers.exec_lua(function()
        if _G.gitsigns_test_repo._watcher ~= nil then
          return false
        end

        for _, handle in ipairs(_G.gitsigns_test_watcher_handles) do
          if not handle:is_closing() then
            return false
          end
        end

        return true
      end)
    end)

    command('Gitsigns attach')

    helpers.expectf(function()
      return helpers.exec_lua(function()
        local bcache = require('gitsigns.cache').cache[vim.api.nvim_get_current_buf()]
        return bcache ~= nil and bcache.git_obj.repo._watcher ~= nil
      end)
    end)

    helpers.exec_lua(function()
      _G.gitsigns_test_repo = nil
      _G.gitsigns_test_watcher_handles = nil
      collectgarbage('collect')
    end)
  end)

  it('gc proxy closes over handles without retaining watcher', function()
    setup_test_repo()
    helpers.setup_path()

    local result = helpers.exec_lua(function(scratch)
      local async = require('gitsigns.async')
      local Repo = require('gitsigns.git.repo')

      local repo, err = async.run(Repo.get, scratch):wait(5000)
      assert(repo, err)
      repo:on_update(function() end)

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

      repo:unref()

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
      repo:on_update(function() end)

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
