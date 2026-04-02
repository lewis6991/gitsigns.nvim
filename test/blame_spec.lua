local helpers = require('test.gs_helpers')

local setup_gitsigns = helpers.setup_gitsigns
local feed = helpers.feed
local edit = helpers.edit
local exec_lua = helpers.exec_lua
local test_config = helpers.test_config
local clear = helpers.clear
local setup_test_repo = helpers.setup_test_repo
local eq = helpers.eq
local check = helpers.check
local expectf = helpers.expectf
local git = helpers.git
local write_to_file = helpers.write_to_file
local scratch --- @type string
local test_file --- @type string

helpers.env()

local function refresh_paths()
  scratch = helpers.scratch
  test_file = helpers.test_file
end

describe('blame', function()
  before_each(function()
    clear()
    refresh_paths()
    helpers.chdir_tmp()
    setup_gitsigns(test_config)
  end)

  it('keeps cursor line on reblame', function()
    setup_test_repo({
      test_file_text = { 'one', 'two', 'three', 'four', 'five' },
    })
    helpers.write_to_file(test_file, { 'ONE', 'two', 'three', 'four', 'five' })
    helpers.git('add', test_file)
    helpers.git('commit', '-m', 'second commit')

    edit(test_file)
    check({
      status = { head = 'main', added = 0, changed = 0, removed = 0 },
      signs = {},
    })
    exec_lua(function()
      local async = require('gitsigns.async')
      async.run(require('gitsigns.actions.blame').blame):raise_on_error()
    end)

    eq(
      true,
      exec_lua(function()
        return vim.wait(10000, function()
          return vim.bo.filetype == 'gitsigns-blame'
        end)
      end)
    )

    local initial_blame_bufname = exec_lua('return vim.api.nvim_buf_get_name(0)')

    feed('3G')
    feed('r')

    eq(
      true,
      exec_lua(function(initial_name)
        return vim.wait(5000, function()
          return vim.bo.filetype == 'gitsigns-blame'
            and vim.api.nvim_buf_get_name(0) ~= initial_name
        end)
      end, initial_blame_bufname)
    )

    eq({ 3, 0 }, helpers.api.nvim_win_get_cursor(0))
    eq('gitsigns-blame', exec_lua('return vim.bo.filetype'))
  end)

  it('uses a repo-relative path when running blame', function()
    local args = exec_lua(function()
      local blame = require('gitsigns.git.blame')

      local captured_args
      local obj = {
        file = 'C:/msys64/home/User/.dotfiles/.config/nvim/lua/mappings.lua',
        relpath = '.config/nvim/lua/mappings.lua',
        object_name = ('a'):rep(40),
        repo = {
          abbrev_head = 'main',
          toplevel = 'C:/msys64/home/User/.dotfiles',
          command = function(_, argv, spec)
            captured_args = vim.deepcopy(argv)
            spec.stdout(
              nil,
              table.concat({
                ('a'):rep(40) .. ' 1 1 1',
                'author tester',
                'author-mail <tester@example.com>',
                'author-time 0',
                'author-tz +0000',
                'committer tester',
                'committer-mail <tester@example.com>',
                'committer-time 0',
                'committer-tz +0000',
                'summary init',
                'filename .config/nvim/lua/mappings.lua',
                '',
              }, '\n')
            )
            return {}, nil, 0
          end,
        },
      }

      blame.run_blame(obj, { 'line' }, 1, nil, {})

      return captured_args
    end)

    eq('--', args[#args - 1])
    eq('.config/nvim/lua/mappings.lua', args[#args])
  end)

  it('blames a tracked file in a nested path', function()
    helpers.git_init_scratch()

    local relpath = '.config/nvim/lua/mappings.lua'
    local file = scratch .. '/' .. relpath

    write_to_file(file, { 'hello', 'world' })
    git('add', file)
    git('commit', '-m', 'add nested mappings')

    edit(file)

    expectf(function()
      return exec_lua(function()
        return vim.b.gitsigns_status_dict.gitdir ~= nil
      end)
    end)

    local result = exec_lua(function(file0)
      local async = require('gitsigns.async')
      return async
        .run(function()
          local Git = require('gitsigns.git')
          local encoding = vim.bo.fileencoding
          if encoding == '' then
            encoding = 'utf-8'
          end

          local obj = assert(Git.Obj.new(file0, nil, encoding))
          local blame_entries = obj:run_blame(nil, 1, nil, {})
          local blame_info = blame_entries and blame_entries[1]
          obj:close()

          return {
            relpath = obj.relpath,
            file = obj.file,
            filename = blame_info and blame_info.filename or '',
            sha = blame_info and blame_info.commit and blame_info.commit.sha or '',
          }
        end)
        :wait(5000)
    end, file)

    eq(relpath, result.relpath)
    eq(false, result.file == result.relpath)
    eq(relpath, result.filename)
    eq(false, result.sha == '')
  end)
end)
