local helpers = require('test.gs_helpers')

local clear = helpers.clear
local eq = helpers.eq
local exec_lua = helpers.exec_lua
local expectf = helpers.expectf
local feed = helpers.feed

helpers.env()

describe('popup', function()
  before_each(function()
    clear()
    helpers.setup_path()
  end)

  it('keeps wrapped lines visible after the parent window scrolls', function()
    local winid, height = exec_lua(function()
      vim.o.columns = 40
      vim.o.lines = 30
      vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.fn['repeat']({ 'x' }, 100))
      vim.api.nvim_win_set_cursor(0, { 10, 0 })

      local long = string.rep('a', 70)
      local winid = require('gitsigns.popup').create(
        { { { long, 'Normal' } }, { { long, 'Normal' } } },
        { relative = 'cursor', row = 1, col = 0 },
        'test'
      )
      return winid, vim.api.nvim_win_get_height(winid)
    end)

    -- Each 70-column line wraps onto two rows of the 40-column popup
    eq(4, height)

    feed('<C-e>')

    expectf(function()
      eq(
        4,
        exec_lua(function(winid0)
          return vim.api.nvim_win_get_height(winid0)
        end, winid)
      )
    end)
  end)
end)
