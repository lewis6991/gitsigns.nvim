local helpers = require('test.functional.helpers')(after_each)
local Screen = require('test.functional.ui.screen')

local clear         = helpers.clear
local command       = helpers.command
local exec_capture  = helpers.exec_capture
local feed          = helpers.feed
local exec_lua      = helpers.exec_lua
local eq            = helpers.eq
local matches       = helpers.matches
local sleep         = helpers.sleep
local split         = helpers.split
local get_buf_var   = helpers.curbufmeths.get_var
local system        = helpers.funcs.system

local pj_root = os.getenv('PJ_ROOT')

local function setup_git()
  -- Always force color to test settings don't interfere with gitsigns systems
  -- commands (addresses #23)
  for k, v in ipairs({
    branch      = 'always',
    ui          = 'always',
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

local function check_status(status)
  eq(get_buf_var('gitsigns_head'), status.head)
  eq(get_buf_var("gitsigns_status_dict"), status)
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

local function cleanup()
  system{"git", "reset"   , "--"  , "scratch"}
  system{"git", "checkout", "--"  , "scratch"}
  system{"git", "clean"   , "-xfd", "scratch"}
end

local function command_fmt(str, ...)
  command(str:format(...))
end


describe('gitsigns', function()
  local screen
  local branch

  setup_git()

  before_each(function()
    clear()
    screen = Screen.new(20, 17)
    screen:attach()
    command('cd '..pj_root)
    branch = helpers.trim(system{"git", "rev-parse", "--abbrev-ref", "HEAD"})

    screen:set_default_attr_ids({
      [1] = {foreground = Screen.colors.DarkBlue, background = Screen.colors.WebGray};
      [2] = {background = Screen.colors.LightMagenta};
      [3] = {background = Screen.colors.LightBlue};
      [4] = {background = Screen.colors.LightCyan1, bold = true, foreground = Screen.colors.Blue1};
      [5] = {foreground = Screen.colors.Brown};
      [6] = {foreground = Screen.colors.Blue1, bold = true};
    })

    exec_lua('package.path = ...', package.path)
  end)

  after_each(function()
    screen:detach()
    cleanup()
  end)

  it('setup', function()
    exec_lua('require("gitsigns").setup()')
  end)

  it('load a file', function()
    exec_lua('require("gitsigns").setup(...)', test_config)
    command_fmt("edit %s/scratch/dummy.txt", pj_root)
    sleep(200)

    local res = split(exec_capture('nmap <buffer>'), '\n')
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
    command_fmt("edit %s/scratch/dummy.txt", pj_root)
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
    sleep(100)

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
    command_fmt("edit %s/scratch/dummy.txt", pj_root)
    command("set signcolumn=yes")

    feed("jjj")
    feed("cc")
    sleep(200)
    feed("EDIT<esc>")
    sleep(100)

    -- Stage
    feed("mhs")
    sleep(100)

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
    sleep(100)

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
    sleep(100)

    screen:expect{grid=[[
      {1:  }This              |
      {1:  }is                |
      {1:  }a                 |
      {1:  }fil^e              |
      {1:  }used              |
                          |
    ]]}

  end)

  it('does not attach inside .git', function()
    exec_lua('require("gitsigns").setup(...)', test_config)
    command_fmt("edit %s/.git/index", pj_root)
    sleep(200)

    local res = split(exec_capture('messages'), '\n')

    eq(res[#res-1], 'attach(1): In git dir')
  end)

  it('numhl works', function()
    local cfg = helpers.deepcopy(test_config)
    cfg.numhl = true
    exec_lua('require("gitsigns").setup(...)', cfg)
    command_fmt("edit %s/scratch/dummy.txt", pj_root)
    command("set signcolumn=no")
    command("set number")

    feed("dd") -- Top delete
    feed("j")
    feed("o<esc>") -- Add
    feed("2j")
    feed("x") -- Change
    feed("3j")
    feed("dd") -- Delete
    feed("j")
    feed("ddx") -- Change delete
    sleep(100)

    -- screen:snapshot_util()
    screen:expect{grid=[[
      {4:  1 }is              |
      {5:  2 }a               |
      {3:  3 }                |
      {5:  4 }file            |
      {2:  5 }sed             |
      {5:  6 }for             |
      {4:  7 }testing         |
      {5:  8 }The             |
      {2:  9 }^oesn't          |
      {5: 10 }matter,         |
      {5: 11 }it              |
      {5: 12 }just            |
      {5: 13 }needs           |
      {5: 14 }to              |
      {5: 15 }be              |
      {5: 16 }static.         |
                          |
    ]]}
  end)

  it('doesn\'t attach to ignored files', function()
    exec_lua('require("gitsigns").setup(...)', test_config)

    system{"touch", pj_root.."/scratch/dummy_ignored.txt"}
    command_fmt("edit %s/scratch/dummy_ignored.txt", pj_root)
    sleep(200)

    local res = split(exec_capture('messages'), '\n')

    eq(res[1], "attach(1): Attaching")
    eq(res[3], "dprint(nil): Running: git rev-parse --show-toplevel --absolute-git-dir --abbrev-ref HEAD")
    matches("Running: git .* ls%-files .*/dummy_ignored.txt", res[5])
    eq(res[7], "attach(1): Cannot resolve file in repo")

    check_status {head=branch}
  end)

  it('doesn\'t attach to non-existent files', function()
    exec_lua('require("gitsigns").setup(...)', test_config)

    system{"rm", pj_root.."/scratch/newfile.txt"}

    command_fmt("edit %s/scratch/newfile.txt", pj_root)
    sleep(100)

    local res = split(exec_capture('messages'), '\n')

    eq(res[1], "attach(1): Attaching")
    eq(res[3], "dprint(nil): Running: git rev-parse --show-toplevel --absolute-git-dir --abbrev-ref HEAD")
    eq(res[5], "attach(1): Not a file")

    check_status {head=branch}

  end)

  it('doesn\'t attach to non-existent files with non-existent sub-dirs', function()
    exec_lua('require("gitsigns").setup(...)', test_config)

    command_fmt("edit %s/does/not/exist", pj_root)
    sleep(100)

    local res = split(exec_capture('messages'), '\n')

    eq(res[1], "attach(1): Attaching")
    eq(res[3], "attach(1): Not a path")

    helpers.pcall_err(get_buf_var, 'gitsigns_head')
    helpers.pcall_err(get_buf_var, "gitsigns_status_dict")

  end)

  it('attaches to newly created files', function()
    screen:try_resize(4, 4)
    exec_lua('require("gitsigns").setup(...)', test_config)

    system{"rm", pj_root.."/scratch/newfile.txt"}
    command_fmt("edit %s/scratch/newfile.txt", pj_root)
    sleep(100)
    command("messages clear")
    command("write")
    sleep(200)

    local res = split(exec_capture('messages'), '\n')

    matches('".*scratch/newfile.txt" %[New] 0L, 0C written', res[1])
    eq(res[2], "attach(1): Attaching")
    eq(res[4], "dprint(nil): Running: git rev-parse --show-toplevel --absolute-git-dir --abbrev-ref HEAD")
    matches("Running: git .* ls%-files .*/newfile.txt", res[6])
    eq(res[8], "dprint(nil): Running: git --no-pager show :scratch/newfile.txt")
    eq(res[10], "get_staged(1): File not in index")
    eq(res[12], "watch_index(1): Watching index")
    matches('Running: git .* diff .* /tmp/lua_.* %-', res[14])
    eq(res[16], "update(1): updates: 1, jobs: 5")

    check_status {head=branch, added=1, changed=0, removed=0}

    screen:expect{grid=[[
      {3:+ }^          |
      {6:~           }|
      {6:~           }|
                  |
    ]]}

  end)

  it('can add untracked files to the index', function()
    screen:try_resize(10, 4)
    exec_lua('require("gitsigns").setup(...)', test_config)

    system{"git", "rm", "-f", pj_root.."/scratch/newfile2.txt"}

    command_fmt("edit %s/scratch/newfile2.txt", pj_root)
    feed("iline<esc>")
    command("write")
    sleep(200)
    command("messages clear")

    -- screen:snapshot_util()
    screen:expect{grid=[[
      {3:+ }lin^e      |
      {6:~           }|
      {6:~           }|
                  |
    ]]}

    feed('mhs') -- Stage the file (add file to index)
    sleep(200)

    screen:expect{grid=[[
      lin^e        |
      {6:~           }|
      {6:~           }|
                  |
    ]]}

  end)

  it('run copen', function()
    exec_lua('require("gitsigns").setup(...)', test_config)

    command("copen")
    local res = split(exec_capture('messages'), '\n')
    eq(res[1], "attach(2): Attaching")
    eq(res[3], "attach(2): Not a path")

  end)

end)
