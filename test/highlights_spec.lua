local Screen = require('nvim-test.screen')
local helpers = require('test.gs_helpers')

local clear = helpers.clear
local command = helpers.api.nvim_command

local cleanup = helpers.cleanup
local test_config = helpers.test_config
local expectf = helpers.expectf
local match_dag = helpers.match_dag
local p = helpers.p
local setup_gitsigns = helpers.setup_gitsigns

helpers.env()

describe('highlights', function()
  local screen --- @type test.screen
  local config --- @type Gitsigns.Config

  before_each(function()
    clear()
    screen = Screen.new(20, 17)
    screen:attach()

    local default_attrs = {
      [1] = { foreground = Screen.colors.DarkBlue, background = Screen.colors.WebGray },
      [2] = { foreground = Screen.colors.NvimDarkCyan },
      [3] = { background = Screen.colors.LightBlue },
      [4] = { foreground = Screen.colors.NvimDarkRed },
      [5] = { foreground = Screen.colors.Brown },
      [6] = { foreground = Screen.colors.Blue1, bold = true },
      [7] = { bold = true },
      [8] = { foreground = Screen.colors.White, background = Screen.colors.Red },
      [9] = { foreground = Screen.colors.SeaGreen, bold = true },
    }

    -- Use the classic vim colorscheme, not the new defaults in nvim >= 0.10
    if helpers.fn.has('nvim-0.10') > 0 then
      command('colorscheme vim')
    else
      default_attrs[2] = { background = Screen.colors.LightMagenta }
      default_attrs[4] =
        { background = Screen.colors.LightCyan1, bold = true, foreground = Screen.colors.Blue1 }
    end

    screen:set_default_attr_ids(default_attrs)

    config = vim.deepcopy(test_config)
  end)

  after_each(function()
    cleanup()
    screen:detach()
  end)

  it('get set up correctly', function()
    command('set termguicolors')

    config.numhl = true
    config.linehl = true
    config._test_mode = true

    setup_gitsigns(config)

    local nvim10 = helpers.fn.has('nvim-0.10') > 0

    expectf(function()
      match_dag({
        p('Deriving GitSignsAdd from ' .. (nvim10 and 'Added' or 'DiffAdd')),
        p('Deriving GitSignsAddLn from DiffAdd'),
        p('Deriving GitSignsAddNr from GitSignsAdd'),
        p('Deriving GitSignsChangeLn from DiffChange'),
        p('Deriving GitSignsChangeNr from GitSignsChange'),
        p('Deriving GitSignsDelete from ' .. (nvim10 and 'Removed' or 'DiffDelete')),
        p('Deriving GitSignsDeleteNr from GitSignsDelete'),
      })
    end)
  end)

  it('update when colorscheme changes', function()
    command('set termguicolors')
    config.linehl = true
    setup_gitsigns(config)
  end)
end)
