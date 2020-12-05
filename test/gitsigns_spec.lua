local helpers = require('test.functional.helpers')(after_each)
local Screen = require('test.functional.ui.screen')

local clear         = helpers.clear
local command       = helpers.command
local exec_capture  = helpers.exec_capture
local feed          = helpers.feed
local exec_lua      = helpers.exec_lua
local eq            = helpers.eq
local sleep         = helpers.sleep
local split         = helpers.split

local function setup_git()
  -- Always force color to test settings don't interfere with gitsigns systems
  -- commands (addresses #23)
  for k, v in ipairs({
    branch      = 'always',
    ui          = 'always',
    branch      = 'always',
    diff        = 'always',
    interactive = 'always',
    status      = 'always',
    grep        = 'always',
    pager       = 'true',
    decorate    = 'always',
    showbranch  = 'always'
  }) do
    os.execute(string.format('git config color.%s %s', k, v))
  end
end

local test_config = {
  debug_mode = true,
  signs = {
    add          = {text = '+'},
    delete       = {text = '_'},
    change       = {text = '~'},
    topdelete    = {text = '^'},
    changedelete = {text = '%'},
  },
  keymaps = {
    noremap = true,
    buffer = true,

    -- ['n ]c'] = { expr = true, "&diff ? ']c' : '<cmd>lua require\"gitsigns\".next_hunk()<CR>'"},
    -- ['n [c'] = { expr = true, "&diff ? '[c' : '<cmd>lua require\"gitsigns\".prev_hunk()<CR>'"},

    ['n mhs'] = '<cmd>lua require"gitsigns".stage_hunk()<CR>',
    ['n mhu'] = '<cmd>lua require"gitsigns".undo_stage_hunk()<CR>',
    ['n mhr'] = '<cmd>lua require"gitsigns".reset_hunk()<CR>',
    ['n mhp'] = '<cmd>lua require"gitsigns".preview_hunk()<CR>',
  }
}


describe('gitsigns', function()
  local screen

  before_each(function()
    clear()
    screen = Screen.new(20, 17)
    screen:attach()
    screen:set_default_attr_ids({
      [1] = {foreground = Screen.colors.DarkBlue, background = Screen.colors.WebGray};
      [2] = {background = Screen.colors.LightMagenta};
      [3] = {background = Screen.colors.LightBlue};
      [4] = {background = Screen.colors.LightCyan1, bold = true, foreground = Screen.colors.Blue1};
    })

    exec_lua('package.path = ...', package.path)
    setup_git()
  end)

  after_each(function()
    screen:detach()
  end)

  it('setup', function()
    exec_lua('require("gitsigns").setup()')
  end)

  it('load a buffer', function()
    exec_lua('require("gitsigns").setup(...)', test_config)
    command("edit ../test/dummy.txt")
    sleep(200)

    local res = split(helpers.exec_capture('nmap <buffer>'), '\n')
    table.sort(res)

    -- Check all keymaps get set
    eq(res, {'',
      'n  mhp         *@<Cmd>lua require"gitsigns".preview_hunk()<CR>',
      'n  mhr         *@<Cmd>lua require"gitsigns".reset_hunk()<CR>',
      'n  mhs         *@<Cmd>lua require"gitsigns".stage_hunk()<CR>',
      'n  mhu         *@<Cmd>lua require"gitsigns".undo_stage_hunk()<CR>',
    })
  end)

  it('basic signs', function()
    exec_lua('require("gitsigns").setup(...)', test_config)
    command("edit ../test/dummy.txt")
    command("set signcolumn=yes")

    feed("dd") -- Top delete
    feed("j")
    feed("o<esc>") -- Add
    feed("2j")
    feed("x") -- Change
    feed("3j")
    feed("dd") -- Delete
    feed("j")
    feed("ddx") -- Change delete

    -- screen:snapshot_util()
    screen:expect{grid=[[
      {4:^ }is                |
      {1:  }a                 |
      {3:+ }                  |
      {1:  }file              |
      {2:~ }sed               |
      {1:  }for               |
      {4:_ }testing           |
      {1:  }The               |
      {2:% }^oesn't            |
      {1:  }matter,           |
      {1:  }it                |
      {1:  }just              |
      {1:  }needs             |
      {1:  }to                |
      {1:  }be                |
      {1:  }static.           |
                          |
    ]]}

  end)

  it('actions', function()
    screen:try_resize(20,6)
    exec_lua('require("gitsigns").setup(...)', test_config)
    command("edit ../test/dummy.txt")
    command("set signcolumn=yes")

    feed("jjj")
    feed("cc")
    sleep(200)
    feed("EDIT<esc>")
    sleep(100)

    -- Stage
    feed("mhs")

    screen:expect{grid=[[
      {1:  }This              |
      {1:  }is                |
      {1:  }a                 |
      {1:  }EDI^T              |
      {1:  }used              |
                          |
    ]]}

    -- Undo stage
    feed("mhu")

    screen:expect{grid=[[
      {1:  }This              |
      {1:  }is                |
      {1:  }a                 |
      {2:~ }EDI^T              |
      {1:  }used              |
                          |
    ]]}

    -- Reset
    feed("mhr")

    screen:expect{grid=[[
      {1:  }This              |
      {1:  }is                |
      {1:  }a                 |
      {1:  }fil^e              |
      {1:  }used              |
                          |
    ]]}

  end)

  it('do not attach inside .git', function()
    exec_lua('require("gitsigns").setup(...)', test_config)
    command("edit ../.git/index")
    sleep(200)

    local res = split(helpers.exec_capture('messages'), '\n')

    eq(res[#res-1], 'attach(1): In git dir')
  end)

end)
