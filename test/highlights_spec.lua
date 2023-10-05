local Screen = require('test.screen')
local helpers = require('test.gs_helpers')

local clear = helpers.clear
local exec_lua = helpers.exec_lua
local command = helpers.api.nvim_command

local cleanup = helpers.cleanup
local test_config = helpers.test_config
local expectf = helpers.expectf
local match_dag = helpers.match_dag
local p = helpers.p
local setup_gitsigns = helpers.setup_gitsigns

helpers.env()

describe('highlights', function()
  local screen
  local config

  before_each(function()
    clear()
    screen = Screen.new(20, 17)
    screen:attach()

    screen:set_default_attr_ids({
      [1] = { foreground = Screen.colors.DarkBlue, background = Screen.colors.WebGray },
      [2] = { background = Screen.colors.LightMagenta },
      [3] = { background = Screen.colors.LightBlue },
      [4] = { background = Screen.colors.LightCyan1, bold = true, foreground = Screen.colors.Blue1 },
      [5] = { foreground = Screen.colors.Brown },
      [6] = { foreground = Screen.colors.Blue1, bold = true },
      [7] = { bold = true },
      [8] = { foreground = Screen.colors.White, background = Screen.colors.Red },
      [9] = { foreground = Screen.colors.SeaGreen, bold = true },
    })

    -- Make gitisigns available
    exec_lua('package.path = ...', package.path)
    exec_lua('gs = require("gitsigns")')
    config = vim.deepcopy(test_config)
  end)

  after_each(function()
    cleanup()
    screen:detach()
  end)
  it('get set up correctly', function()
    command('set termguicolors')

    config.signs.add.hl = nil
    config.signs.change.hl = nil
    config.signs.delete.hl = nil
    config.signs.changedelete.hl = nil
    config.signs.topdelete.hl = nil
    config.numhl = true
    config.linehl = true
    config._test_mode = true

    setup_gitsigns(config)

    expectf(function()
      match_dag({
        p('Deriving GitSignsAdd from DiffAdd'),
        p('Deriving GitSignsAddLn from DiffAdd'),
        p('Deriving GitSignsAddNr from GitSignsAdd'),
        p('Deriving GitSignsChangeLn from DiffChange'),
        p('Deriving GitSignsChangeNr from GitSignsChange'),
        p('Deriving GitSignsDelete from DiffDelete'),
        p('Deriving GitSignsDeleteNr from GitSignsDelete'),
      })
    end)

    -- eq('GitSignsChange xxx links to DiffChange',
    -- exec_capture('hi GitSignsChange'))

    -- eq('GitSignsDelete xxx links to DiffDelete',
    -- exec_capture('hi GitSignsDelete'))

    -- eq('GitSignsAdd    xxx links to DiffAdd',
    -- exec_capture('hi GitSignsAdd'))
  end)

  it('update when colorscheme changes', function()
    command('set termguicolors')

    config.signs.add.hl = nil
    config.signs.change.hl = nil
    config.signs.delete.hl = nil
    config.signs.changedelete.hl = nil
    config.signs.topdelete.hl = nil
    config.linehl = true

    setup_gitsigns(config)

    -- expectf(function()
    --   eq('GitSignsChange xxx links to DiffChange',
    --     exec_capture('hi GitSignsChange'))

    --   eq('GitSignsDelete xxx links to DiffDelete',
    --     exec_capture('hi GitSignsDelete'))

    --   eq('GitSignsAdd    xxx links to DiffAdd',
    --     exec_capture('hi GitSignsAdd'))

    --   eq('GitSignsAddLn  xxx links to DiffAdd',
    --     exec_capture('hi GitSignsAddLn'))
    -- end)

    -- command('colorscheme blue')

    -- expectf(function()
    --   eq('GitSignsChange xxx links to DiffChange',
    --     exec_capture('hi GitSignsChange'))

    --   eq('GitSignsDelete xxx links to DiffDelete',
    --     exec_capture('hi GitSignsDelete'))

    --   eq('GitSignsAdd    xxx links to DiffAdd',
    --     exec_capture('hi GitSignsAdd'))

    --   eq('GitSignsAddLn  xxx links to DiffAdd',
    --     exec_capture('hi GitSignsAddLn'))
    -- end)
  end)
end)
