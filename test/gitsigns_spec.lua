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
  },
  update_debounce = 10
}

local function cleanup()
  system{"git", "reset"   , "--"  , "scratch"}
  system{"git", "checkout", "--"  , "scratch"}
  system{"git", "clean"   , "-xfd", "scratch"}
end

local function command_fmt(str, ...)
  command(str:format(...))
end

local function buf_var_exists(name)
  return pcall(get_buf_var, name)
end

local function match_lines(lines, spec)
  local i = 1
  for _, line in ipairs(lines) do
    if line ~= '' then
      local s = spec[i]
      if s then
        if s.pattern then
          matches(s.text, line)
        else
          eq(s, line)
        end
      else
        error('Unexpected extra text: '..line)
      end
      i = i + 1
    end
  end
end

local function match_messages(spec)
  local res = split(exec_capture('messages'), '\n')
  match_lines(res, spec)
end

local function p(str)
  return {text=str, pattern=true}
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
    sleep(20)

    local res = split(exec_capture('nmap <buffer>'), '\n')
    table.sort(res)

    -- Check all keymaps get set
    match_lines(res, {
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
    sleep(10)

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
    sleep(20)
    feed("EDIT<esc>")
    sleep(10)

    screen:expect{grid=[[
      {1:  }This              |
      {1:  }is                |
      {1:  }a                 |
      {2:~ }EDI^T              |
      {1:  }used              |
                          |
    ]]}

    -- Stage
    feed("mhs")
    sleep(10)

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
    sleep(10)

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
    sleep(10)

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
    sleep(20)

    match_messages {
      'attach(1): Attaching',
      'attach(1): In git dir'
    }
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
    sleep(20)

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
    sleep(20)

    match_messages {
      "attach(1): Attaching",
      "dprint(nil): Running: git rev-parse --show-toplevel --absolute-git-dir --abbrev-ref HEAD",
      p"Running: git .* ls%-files .*/dummy_ignored.txt",
      "attach(1): Cannot resolve file in repo",
    }

    check_status {head=branch}
  end)

  it('doesn\'t attach to non-existent files', function()
    exec_lua('require("gitsigns").setup(...)', test_config)

    system{"rm", pj_root.."/scratch/newfile.txt"}

    command_fmt("edit %s/scratch/newfile.txt", pj_root)
    sleep(10)

    match_messages {
      "attach(1): Attaching",
      "dprint(nil): Running: git rev-parse --show-toplevel --absolute-git-dir --abbrev-ref HEAD",
      "attach(1): Not a file",
    }

    check_status {head=branch}

  end)

  it('doesn\'t attach to non-existent files with non-existent sub-dirs', function()
    exec_lua('require("gitsigns").setup(...)', test_config)

    command_fmt("edit %s/does/not/exist", pj_root)
    sleep(10)

    match_messages {
      "attach(1): Attaching",
      "attach(1): Not a path",
    }

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
    sleep(20)

    match_messages {
      p'".*scratch/newfile.txt" %[New] 0L, 0C written',
      "attach(1): Attaching",
      "dprint(nil): Running: git rev-parse --show-toplevel --absolute-git-dir --abbrev-ref HEAD",
      p"Running: git .* ls%-files .*/newfile.txt",
      "watch_index(1): Watching index",
      "dprint(nil): Running: git --no-pager show :0:scratch/newfile.txt",
      p'Running: git .* diff .* /tmp/lua_.* %-',
      "update(1): updates: 1, jobs: 5"
    }

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
    sleep(20)
    command("messages clear")

    -- screen:snapshot_util()
    screen:expect{grid=[[
      {3:+ }lin^e      |
      {6:~           }|
      {6:~           }|
                  |
    ]]}

    feed('mhs') -- Stage the file (add file to index)
    sleep(20)

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

    match_messages {
      "attach(2): Attaching",
      "attach(2): Non-normal buffer",
    }

  end)

  it('tracks files in new repos', function()
    screen:try_resize(10, 4)
    exec_lua('require("gitsigns").setup(...)', test_config)
    local d = '/tmp/sample_proj'
    system{"rm", "-rf", d}
    system{"mkdir", "-p", d}
    system{"git", "-C", d, "init"}
    system{"touch", d.."/a"}
    command("edit "..d.."/a")

    feed("iEDIT<esc>")
    command("write")

    screen:expect{grid=[[
      {3:+ }EDI^T      |
      {6:~           }|
      {6:~           }|
                  |
    ]]}

    -- Stage
    system{"git", "-C", d, "add", "a"}

    screen:expect{grid=[[
      EDI^T        |
      {6:~           }|
      {6:~           }|
                  |
    ]]}

    -- -- Reset
    system{"git", "-C", d, "reset"}

    screen:expect{grid=[[
      {3:+ }EDI^T      |
      {6:~           }|
      {6:~           }|
                  |
    ]]}

  end)

  it('can detach from buffers', function()
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
    sleep(10)

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

    exec_lua('require("gitsigns").detach()')

    screen:expect{grid=[[
      {1:  }is                |
      {1:  }a                 |
      {1:  }                  |
      {1:  }file              |
      {1:  }sed               |
      {1:  }for               |
      {1:  }testing           |
      {1:  }The               |
      {1:  }^oesn't            |
      {1:  }matter,           |
      {1:  }it                |
      {1:  }just              |
      {1:  }needs             |
      {1:  }to                |
      {1:  }be                |
      {1:  }static.           |
                          |
    ]]}

    assert(not buf_var_exists('gitsigns_head'),
      'gitsigns_status_dict should not be defined')

    assert(not buf_var_exists('gitsigns_status_dict'),
      'gitsigns_head should not be defined')

    assert(not buf_var_exists('gitsigns_status'),
      'gitsigns_status should not be defined')
  end)

end)
