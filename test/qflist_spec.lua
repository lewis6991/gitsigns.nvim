local helpers = require('test.gs_helpers')

local clear = helpers.clear
local cleanup = helpers.cleanup
local command = helpers.api.nvim_command
local eq = helpers.eq
local exec_lua = helpers.exec_lua
local git = helpers.git
local scratch = helpers.scratch
local setup_gitsigns = helpers.setup_gitsigns
local setup_test_repo = helpers.setup_test_repo
local system = helpers.fn.system
local test_config = helpers.test_config
local test_file = helpers.test_file

helpers.env()

describe('qflist', function()
  before_each(function()
    clear()
    command('cd ' .. system({ 'dirname', os.tmpname() }))
  end)

  after_each(function()
    cleanup()
  end)

  it('diffs renamed files against their base path when using a base revision', function()
    setup_test_repo()
    command('cd ' .. scratch)
    setup_gitsigns(vim.tbl_extend('force', test_config, { base = 'HEAD' }))

    local renamed = test_file .. '2'
    git('mv', test_file, renamed)
    exec_lua(function(path)
      local lines = vim.fn.readfile(path)
      lines[2] = 'renamed and edited'
      vim.fn.writefile(lines, path)
    end, renamed)

    exec_lua(function()
      require('gitsigns.actions').setqflist('all', { open = false })
    end)

    helpers.expectf(function()
      local items, names, texts = exec_lua(function()
        local items0 = vim.fn.getqflist()
        local names0 = {} --- @type string[]
        local texts0 = {} --- @type string[]
        for i, item in ipairs(items0) do
          names0[i] = item.filename or vim.api.nvim_buf_get_name(item.bufnr)
          texts0[i] = item.text
        end
        return items0, names0, texts0
      end) --- @type vim.quickfix.entry[], string[], string[]

      eq(1, #items)
      eq(renamed, names[1])
      eq(true, texts[1]:match('^Changed') ~= nil)
    end)
  end)
end)
