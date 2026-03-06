local helpers = require('test.gs_helpers')

local setup_gitsigns = helpers.setup_gitsigns
local feed = helpers.feed
local test_file = helpers.test_file
local edit = helpers.edit
local exec_lua = helpers.exec_lua
local fn = helpers.fn
local system = fn.system
local test_config = helpers.test_config
local clear = helpers.clear
local setup_test_repo = helpers.setup_test_repo
local eq = helpers.eq
local check = helpers.check

helpers.env()

describe('blame', function()
  before_each(function()
    clear()
    helpers.api.nvim_command('cd ' .. system({ 'dirname', os.tmpname() }))
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
end)
