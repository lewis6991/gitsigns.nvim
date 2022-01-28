local helpers = require('test.gs_helpers')
local exec_lua = helpers.exec_lua
local setup_gitsigns  = helpers.setup_gitsigns
local clear           = helpers.clear

describe('unit', function()
  it('passes all _TEST blocks', function()
    clear()
    exec_lua('package.path = ...', package.path)
    exec_lua('_TEST = true')
    setup_gitsigns()
  end)
end)
