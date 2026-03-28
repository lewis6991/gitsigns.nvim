local helpers = require('test.gs_helpers')

local clear = helpers.clear
local eq = helpers.eq
local exec_lua = helpers.exec_lua

helpers.env()

local function contains_hl(hl, group)
  if type(hl) == 'table' then
    return vim.tbl_contains(hl, group)
  end
  return hl == group
end

local function virt_hl_at_col(vline, col)
  local byte_col = 0
  for _, chunk in ipairs(vline) do
    local text, hl = chunk[1], chunk[2]
    local next_col = byte_col + #text
    if col < next_col then
      return hl
    end
    byte_col = next_col
  end
end

describe('render.virt', function()
  before_each(function()
    clear()
    helpers.setup_path()
  end)

  it('renders layered captured lines and extends eol fill with padding', function()
    local vline, width = exec_lua(function()
      local Virt = require('gitsigns.render.virt')
      local text = 'local foo = 1'
      local lines = {
        {
          text = text,
          layers = {
            {
              start_col = 0,
              end_col = #text,
              priority = 1000,
              hl_group = 'GitSignsDeleteVirtLn',
            },
            {
              start_col = 6,
              end_col = 9,
              priority = 1001,
              hl_group = 'GitSignsDeleteVirtLnInLine',
            },
          },
        },
      }

      local rendered = Virt.render(lines, { pad_width = 24 })
      local row = assert(rendered[1])
      local text0 = {}
      for _, chunk in ipairs(row) do
        text0[#text0 + 1] = chunk[1]
      end

      return row, vim.fn.strdisplaywidth(table.concat(text0))
    end)

    eq(24, width)
    assert(contains_hl(virt_hl_at_col(vline, 0), 'GitSignsDeleteVirtLn'))
    assert(contains_hl(virt_hl_at_col(vline, 7), 'GitSignsDeleteVirtLnInLine'))
    assert(contains_hl(virt_hl_at_col(vline, 20), 'GitSignsDeleteVirtLn'))
  end)

  it('prepends per-line virtual prefixes without mutating input', function()
    local out_first, out_second, prefix_first = exec_lua(function()
      local Virt = require('gitsigns.render.virt')
      local lines = {
        {
          text = 'alpha',
          layers = {
            { start_col = 0, end_col = 5, priority = 1000, hl_group = 'GitSignsDeleteVirtLn' },
          },
        },
        {
          text = 'beta',
          layers = {
            { start_col = 0, end_col = 4, priority = 1000, hl_group = 'GitSignsDeleteVirtLn' },
          },
        },
      }

      local prefixes = {
        { { '1 ', 'LineNr' } },
        { { '2 ', 'LineNr' } },
      }
      local rendered = Virt.render(lines, { prefix = prefixes })
      return rendered[1][1][1], rendered[2][1][1], prefixes[1][1][1]
    end)

    eq('1 ', out_first)
    eq('2 ', out_second)
    eq('1 ', prefix_first)
  end)
end)
