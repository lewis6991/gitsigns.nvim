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
local setup_gitsigns = helpers.setup_gitsigns
local test_file = helpers.test_file
local git = helpers.git

helpers.env()

local function get_bufs()
  local bufs = {} --- @type table<integer,string>
  for _, b in ipairs(helpers.api.nvim_list_bufs()) do
    bufs[b] = helpers.api.nvim_buf_get_name(b)
  end
  return bufs
end

describe('gitdir_watcher', function()
  before_each(function()
    clear()
    command('cd ' .. system({ 'dirname', os.tmpname() }))
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
      np('system.system: git .* ls%-files .* ' .. vim.pesc(test_file)),
      np('attach%.attach%(1%): Watching git dir .*'),
      np('system.system: git .* show .*'),
    })

    eq({ [1] = test_file }, get_bufs())

    command('Gitsigns clear_debug')

    local test_file2 = test_file .. '2'
    git('mv', test_file, test_file2)

    match_debug_messages({
      p('git.repo.watcher.watcher.handler: Git dir update: .*'),
      np('system.system: git .* ls%-files .* ' .. vim.pesc(test_file)),
      np('system.system: git .* diff %-%-name%-status .* %-%-cached'),
      n('attach.handle_moved(1): File moved to dummy.txt2'),
      np('system.system: git .* ls%-files .* ' .. vim.pesc(test_file2)),
      np('attach%.handle_moved%(1%): Renamed buffer 1 from .*/dummy.txt to .*/dummy.txt2'),
      np('system.system: git .* show .*'),
    })

    eq({ [1] = test_file2 }, get_bufs())

    command('Gitsigns clear_debug')

    local test_file3 = test_file .. '3'

    git('mv', test_file2, test_file3)

    match_debug_messages({
      p('git.repo.watcher.watcher.handler: Git dir update: .*'),
      np('system.system: git .* ls%-files .* ' .. vim.pesc(test_file2)),
      np('system.system: git .* diff %-%-name%-status .* %-%-cached'),
      n('attach.handle_moved(1): File moved to dummy.txt3'),
      np('system.system: git .* ls%-files .* ' .. vim.pesc(test_file3)),
      np('attach%.handle_moved%(1%): Renamed buffer 1 from .*/dummy.txt2 to .*/dummy.txt3'),
      np('system.system: git .* show .*'),
    })

    eq({ [1] = test_file3 }, get_bufs())

    command('Gitsigns clear_debug')

    git('mv', test_file3, test_file)

    match_debug_messages({
      p('git.repo.watcher.watcher.handler: Git dir update: .*'),
      np('system.system: git .* ls%-files .* ' .. vim.pesc(test_file3)),
      np('system.system: git .* diff %-%-name%-status .* %-%-cached'),
      np('system.system: git .* ls%-files .* ' .. vim.pesc(test_file)),
      n('attach.handle_moved(1): Moved file reset'),
      np('system.system: git .* ls%-files .* ' .. vim.pesc(test_file)),
      np('attach%.handle_moved%(1%): Renamed buffer 1 from .*/dummy.txt3 to .*/dummy.txt'),
      np('system.system: git .* show .*'),
    })

    eq({ [1] = test_file }, get_bufs())
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
      local handle = watcher.handle

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

        return weak[1] == nil
          and weak[2] == nil
          and repo_cache[gitdir] == nil
          and handle:is_closing()
      end, 20, false)

      return {
        repo_gced = weak[1] == nil,
        watcher_gced = weak[2] == nil,
        cache_cleared = repo_cache[gitdir] == nil,
        handle_closed = handle:is_closing(),
      }
    end, helpers.scratch)

    eq(true, result.repo_gced)
    eq(true, result.watcher_gced)
    eq(true, result.cache_cleared)
    eq(true, result.handle_closed)
  end)
end)
