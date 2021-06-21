local Screen = require('test.functional.ui.screen')
local helpers = require('test.gs_helpers')

local clear         = helpers.clear
local exec_lua      = helpers.exec_lua
local command       = helpers.command
local eq            = helpers.eq
local exec_capture  = helpers.exec_capture

local cleanup       = helpers.cleanup
local test_config   = helpers.test_config
local wait          = helpers.wait
local match_dag     = helpers.match_dag
local debug_messages = helpers.debug_messages
local p             = helpers.p
local setup         = helpers.setup

local it = helpers.it(it)

describe('highlights', function()
  local screen
  local config

  before_each(function()
    clear()
    screen = Screen.new(20, 17)
    screen:attach()

    screen:set_default_attr_ids({
      [1] = {foreground = Screen.colors.DarkBlue, background = Screen.colors.WebGray};
      [2] = {background = Screen.colors.LightMagenta};
      [3] = {background = Screen.colors.LightBlue};
      [4] = {background = Screen.colors.LightCyan1, bold = true, foreground = Screen.colors.Blue1};
      [5] = {foreground = Screen.colors.Brown};
      [6] = {foreground = Screen.colors.Blue1, bold = true};
      [7] = {bold = true},
      [8] = {foreground = Screen.colors.White, background = Screen.colors.Red};
      [9] = {foreground = Screen.colors.SeaGreen, bold = true};
    })

    -- Make gitisigns available
    exec_lua('package.path = ...', package.path)
    exec_lua('gs = require("gitsigns")')
    config = helpers.deepcopy(test_config)
  end)

  after_each(function()
    cleanup()
    screen:detach()
  end)
  it('get set up correctly', function()
    command("set termguicolors")

    config.signs.add.hl = nil
    config.signs.change.hl = nil
    config.signs.delete.hl = nil
    config.signs.changedelete.hl = nil
    config.signs.topdelete.hl = nil
    config.numhl = true
    config.linehl = true

    exec_lua('gs.setup(...)', config)

    wait(function()
      match_dag(debug_messages(), {
        p'Deriving GitSignsChangeNr from GitSignsChange',
        p'Deriving GitSignsChangeLn from GitSignsChange',
        p'Deriving GitSignsDelete from DiffDelete',
        p'Deriving GitSignsDeleteNr from GitSignsDelete',
        p'Deriving GitSignsDeleteLn from GitSignsDelete',
        p'Deriving GitSignsAdd from DiffAdd',
        p'Deriving GitSignsAddNr from GitSignsAdd',
        p'Deriving GitSignsAddLn from GitSignsAdd',
        p'Deriving GitSignsDeleteNr from GitSignsDelete',
        p'Deriving GitSignsDeleteLn from GitSignsDelete',
        p'Deriving GitSignsChangeNr from GitSignsChange',
        p'Deriving GitSignsChangeLn from GitSignsChange'
      })
    end)

    eq('GitSignsChange xxx gui=reverse guibg=#ffbbff',
      exec_capture('hi GitSignsChange'))

    eq('GitSignsDelete xxx gui=reverse guifg=#0000ff guibg=#e0ffff',
      exec_capture('hi GitSignsDelete'))

    eq('GitSignsAdd    xxx gui=reverse guibg=#add8e6',
      exec_capture('hi GitSignsAdd'))
  end)

  it('update when colorscheme changes', function()
    command("set termguicolors")

    config.signs.add.hl = nil
    config.signs.change.hl = nil
    config.signs.delete.hl = nil
    config.signs.changedelete.hl = nil
    config.signs.topdelete.hl = nil
    config.linehl = true

    setup(config)

    wait(function()
      eq('GitSignsChange xxx gui=reverse guibg=#ffbbff',
        exec_capture('hi GitSignsChange'))

      eq('GitSignsDelete xxx gui=reverse guifg=#0000ff guibg=#e0ffff',
        exec_capture('hi GitSignsDelete'))

      eq('GitSignsAdd    xxx gui=reverse guibg=#add8e6',
        exec_capture('hi GitSignsAdd'))

      eq('GitSignsAddLn  xxx gui=reverse guibg=#add8e6',
        exec_capture('hi GitSignsAddLn'))
    end)

    command('colorscheme blue')

    wait(function()
      eq('GitSignsChange xxx gui=reverse guifg=#000000 guibg=#006400',
        exec_capture('hi GitSignsChange'))

      eq('GitSignsDelete xxx gui=reverse guifg=#000000 guibg=#ff7f50',
        exec_capture('hi GitSignsDelete'))

      eq('GitSignsAdd    xxx gui=reverse guifg=#000000 guibg=#6a5acd',
        exec_capture('hi GitSignsAdd'))

      eq('GitSignsAddLn  xxx gui=reverse guifg=#000000 guibg=#6a5acd',
        exec_capture('hi GitSignsAddLn'))
    end)
  end)
end)
