-- vim: foldnestmax=5:

local Screen = require('test.functional.ui.screen')
local helpers = require('test.gs_helpers')

local clear         = helpers.clear
local command       = helpers.command
local exec_capture  = helpers.exec_capture
local feed          = helpers.feed
local exec_lua      = helpers.exec_lua
local eq            = helpers.eq
local split         = helpers.split
local get_buf_var   = helpers.curbufmeths.get_var
local fn            = helpers.funcs
local system        = fn.system
local init          = helpers.init
local wait          = helpers.wait
local write_to_file = helpers.write_to_file
local edit          = helpers.edit
local cleanup       = helpers.cleanup
local test_file     = helpers.test_file
local git           = helpers.git
local scratch       = helpers.scratch
local newfile       = helpers.newfile
local debug_messages = helpers.debug_messages
local match_dag     = helpers.match_dag
local match_debug_messages = helpers.match_debug_messages
local match_lines   = helpers.match_lines
local p             = helpers.p
local setup         = helpers.setup
local test_config   = helpers.test_config

local it = helpers.it(it)

local function check_status(status)
  wait(function()
    eq(1, fn.exists('b:gitsigns_head'))
    eq(status.head, get_buf_var('gitsigns_head'))
    eq(status, get_buf_var("gitsigns_status_dict"))
  end)
end

local function buf_var_exists(name)
  return pcall(get_buf_var, name)
end

describe('gitsigns', function()
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
    config = helpers.deepcopy(test_config)
  end)

  after_each(function()
    cleanup()
    screen:detach()
  end)

  it('can run basic setup', function()
    screen:try_resize(60,6)
    setup()
    screen:expect{grid=[[
      ^                                                            |
      {6:~                                                           }|
      {6:~                                                           }|
      {6:~                                                           }|
      {6:~                                                           }|
                                                                  |
    ]]}
  end)

  it('index watcher works on a fresh repo', function()
    screen:try_resize(20,6)
    init(true)
    config.watch_index = {interval = 5}
    setup(config)
    edit(test_file)

    wait(function()
      match_dag(debug_messages(), {
        "run_job: git --no-pager --version",
        'attach(1): Attaching',
        p'run_job: git .* config user.name',
        'run_job: git --no-pager rev-parse --show-toplevel --absolute-git-dir --abbrev-ref HEAD',
        p('run_job: git .* ls%-files %-%-stage %-%-others %-%-exclude%-standard '..test_file),
        'watch_index(1): Watching index',
        'watcher_cb(1): Index update error: ENOENT',
        p'run_job: git .* show :0:dummy.txt',
        'update(1): updates: 1, jobs: 5'
      })
    end)

    screen:expect{grid=[[
      {3:+ }^This              |
      {3:+ }is                |
      {3:+ }a                 |
      {3:+ }file              |
      {3:+ }used              |
                          |
    ]]}

    git{"add", test_file}

    screen:expect{grid=[[
      ^This                |
      is                  |
      a                   |
      file                |
      used                |
                          |
    ]]}
  end)

  it('can open files not in a git repo', function()
    screen:try_resize(60,6)
    setup(config)
    local tmpfile = os.tmpname()
    edit(tmpfile)
    screen:expect{grid=[[
      ^                                                            |
      {6:~                                                           }|
      {6:~                                                           }|
      {6:~                                                           }|
      {6:~                                                           }|
                                                                  |
    ]]}
    feed('iline<esc>')
    command("write")
    screen:expect{grid=([[
      lin^e                                                        |
      {6:~                                                           }|
      {6:~                                                           }|
      {6:~                                                           }|
      {6:~                                                           }|
      "%s" 1L, 5C written                            |
    ]]):format(tmpfile)}

    match_debug_messages {
      "run_job: git --no-pager --version",
      'attach(1): Attaching',
      p"run_job: git .* config user.name",
      "run_job: git --no-pager rev-parse --show-toplevel --absolute-git-dir --abbrev-ref HEAD",
      'attach(1): Not in git repo',
      'attach(1): Attaching',
      'run_job: git --no-pager config user.name',
      'run_job: git --no-pager rev-parse --show-toplevel --absolute-git-dir --abbrev-ref HEAD',
      'attach(1): Not in git repo'
    }
  end)

  describe('when attaching', function()
    before_each(function()
      init()
      setup(config)
    end)

    it('can setup mappings', function()
      edit(test_file)
      wait(function()
        local res = split(exec_capture('nmap <buffer>'), '\n')
        table.sort(res)

        -- Check all keymaps get set
        match_lines(res, {
          'n  mhS         *@<Cmd>lua require"gitsigns".stage_buffer()<CR>',
          'n  mhU         *@<Cmd>lua require"gitsigns".reset_buffer_index()<CR>',
          'n  mhp         *@<Cmd>lua require"gitsigns".preview_hunk()<CR>',
          'n  mhr         *@<Cmd>lua require"gitsigns".reset_hunk()<CR>',
          'n  mhs         *@<Cmd>lua require"gitsigns".stage_hunk()<CR>',
          'n  mhu         *@<Cmd>lua require"gitsigns".undo_stage_hunk()<CR>',
        })
      end)
    end)

    it('does not attach inside .git', function()
      edit(scratch..'/.git/index')

      match_debug_messages {
        "run_job: git --no-pager --version",
        'attach(1): Attaching',
        'attach(1): In git dir'
      }
    end)

    it('doesn\'t attach to ignored files', function()
      write_to_file(scratch..'/.gitignore', {'dummy_ignored.txt'})

      local ignored_file = scratch.."/dummy_ignored.txt"

      system{"touch", ignored_file}
      edit(ignored_file)

      match_debug_messages {
        "run_job: git --no-pager --version",
        "attach(1): Attaching",
        p"run_job: git .* config user.name",
        "run_job: git --no-pager rev-parse --show-toplevel --absolute-git-dir --abbrev-ref HEAD",
        p"run_job: git .* ls%-files .*/dummy_ignored.txt",
        "attach(1): Cannot resolve file in repo",
      }

      check_status {head='master'}
    end)

    it('doesn\'t attach to non-existent files', function()
      edit(newfile)

      match_debug_messages {
        "run_job: git --no-pager --version",
        "attach(1): Attaching",
        p"run_job: git .* config user.name",
        "run_job: git --no-pager rev-parse --show-toplevel --absolute-git-dir --abbrev-ref HEAD",
        p("run_job: git .* ls%-files %-%-stage %-%-others %-%-exclude%-standard "..newfile),
        "attach(1): Not a file",
      }

      check_status {head='master'}

    end)

    it('doesn\'t attach to non-existent files with non-existent sub-dirs', function()
      edit(scratch..'/does/not/exist')

      match_debug_messages {
        "run_job: git --no-pager --version",
        "attach(1): Attaching",
        "attach(1): Not a path",
      }

      helpers.pcall_err(get_buf_var, 'gitsigns_head')
      helpers.pcall_err(get_buf_var, 'gitsigns_status_dict')

    end)

    it('can run copen', function()
      command("copen")
      match_debug_messages {
        "run_job: git --no-pager --version",
        "attach(2): Attaching",
        "attach(2): Non-normal buffer",
      }
    end)
  end)

  describe('current line blame', function()
    it('doesn\'t error on untracked files', function()
      command("set updatetime=1")
      init(true)
      screen:detach()
      screen:attach({ext_messages=true})
      config.current_line_blame = true
      setup(config)
      edit(newfile)
      feed("iline<esc>")
      command("write")
      screen:expect{messages = { { content = { { "<" } }, kind = "" } } }
    end)
  end)

  describe('on_attach()', function()
    it('can prevent attaching to a buffer', function()
      init(true)

      -- Functions can't be serialized over rpc so need to setup config
      -- remotely
      exec_lua('config = ...', config)
      exec_lua[[config.on_attach = function()
        return false
      end]]
      exec_lua('require("gitsigns").setup(config)')
      wait(function()
        exec_capture('au gitsigns')
      end)
      edit(test_file)
      match_debug_messages {
        "run_job: git --no-pager --version",
        'attach(1): Attaching',
        p"run_job: git .* config user.name",
        "run_job: git --no-pager rev-parse --show-toplevel --absolute-git-dir --abbrev-ref HEAD",
        p'run_job: git %-%-no%-pager %-%-git%-dir=.* %-%-stage %-%-others %-%-exclude%-standard .*',
        "attach(1): User on_attach() returned false",
      }
    end)
  end)

  describe('change_base()', function()
    it('works', function()
      screen:try_resize(20, 4)

      init()
      edit(test_file)

      feed('oEDIT<esc>')
      command('write')

      git{'add', test_file}
      git{"commit", "-m", "commit on main"}

      -- Don't setup gitsigns until the repo has two commits
      setup(config)

      screen:expect{
        grid=[[
          This                |
          EDI^T                |
          is                  |
          < 19L, 103C written |
        ]],
        condition = function()
          return fn.exists('#gitsigns') > 0
        end,
      }

      command('Gitsigns change_base ~')
      screen:expect[[
        {1:  }This              |
        {3:+ }EDI^T              |
        {1:  }is                |
        < 19L, 103C written |
      ]]
    end)
  end)

  local function testsuite(advanced_features)
    return function()
      before_each(function()
        config.use_decoration_api = advanced_features
        config.use_internal_diff = advanced_features
        init()
      end)

      it('apply basic signs', function()
        setup(config)
        edit(test_file)
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

      it('perform actions', function()
        screen:try_resize(20,6)
        setup(config)
        edit(test_file)
        command("set signcolumn=yes")

        feed("jjj")
        feed("cc")
        feed("EDIT<esc>")

        -- screen:snapshot_util()
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

        screen:expect{grid=[[
          {1:  }This              |
          {1:  }is                |
          {1:  }a                 |
          {1:  }EDI^T              |
          {1:  }used              |
                              |
        ]]}
        check_status {head='master', added=0, changed=0, removed=0}

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
        check_status {head='master', added=0, changed=1, removed=0}

        -- Add multiple edits
        feed('gg')
        feed('cc')
        feed('That<esc>')

        screen:expect{grid=[[
          {2:~ }Tha^t              |
          {1:  }is                |
          {1:  }a                 |
          {2:~ }EDIT              |
          {1:  }used              |
                              |
        ]]}
        check_status {head='master', added=0, changed=2, removed=0}

        -- Stage buffer
        feed("mhS")

        screen:expect{grid=[[
          {1:  }Tha^t              |
          {1:  }is                |
          {1:  }a                 |
          {1:  }EDIT              |
          {1:  }used              |
                              |
        ]]}
        check_status {head='master', added=0, changed=0, removed=0}

        -- Unstage buffer
        feed("mhU")

        screen:expect{grid=[[
          {2:~ }Tha^t              |
          {1:  }is                |
          {1:  }a                 |
          {2:~ }EDIT              |
          {1:  }used              |
                              |
        ]]}
        check_status {head='master', added=0, changed=2, removed=0}

        -- Reset
        feed("mhr")

        screen:expect{grid=[[
          {1:  }Thi^s              |
          {1:  }is                |
          {1:  }a                 |
          {2:~ }EDIT              |
          {1:  }used              |
                              |
        ]]}
        check_status {head='master', added=0, changed=1, removed=0}
      end)

      it('can enable numhl', function()
        config.numhl = true
        setup(config)
        edit(test_file)
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

      it('attaches to newly created files', function()
        screen:try_resize(4, 4)
        setup(config)
        edit(newfile)
        match_debug_messages{
          'run_job: git --no-pager --version',
          'attach(1): Attaching',
          'run_job: git --no-pager config user.name',
          'run_job: git --no-pager rev-parse --show-toplevel --absolute-git-dir --abbrev-ref HEAD',
          p'run_job: git .* ls%-files .*',
          'attach(1): Not a file',
        }
        command('Gitsigns clear_debug')
        command("write")

        local messages = {
          "attach(1): Attaching",
          p"run_job: git .* config user.name",
          "run_job: git --no-pager rev-parse --show-toplevel --absolute-git-dir --abbrev-ref HEAD",
          p"run_job: git .* ls%-files .*",
          "watch_index(1): Watching index",
          p"run_job: git .* show :0:newfile.txt"
        }

        if not advanced_features then
          table.insert(messages, p'run_job: git .* diff .* /tmp/lua_.* /tmp/lua_.*')
        end

        local jobs = advanced_features and 8 or 9
        table.insert(messages, "update(1): updates: 1, jobs: "..jobs)

        match_debug_messages(messages)

        check_status {head='master', added=1, changed=0, removed=0}

        screen:expect{grid=[[
          {3:+ }^          |
          {6:~           }|
          {6:~           }|
          <0C written |
        ]]}

      end)

      it('can add untracked files to the index', function()
        screen:try_resize(10, 4)
        setup(config)

        edit(newfile)
        feed("iline<esc>")
        check_status {head='master'}
        command("write")
        check_status {head='master', added=1, changed=0, removed=0}

        -- screen:snapshot_util()
        screen:expect{grid=[[
          {3:+ }lin^e      |
          {6:~           }|
          {6:~           }|
          <5C written |
        ]]}

        feed('mhs') -- Stage the file (add file to index)

        check_status {head='master', added=0, changed=0, removed=0}
        screen:expect{grid=[[
          lin^e        |
          {6:~           }|
          {6:~           }|
          <5C written |
        ]]}

      end)

      it('tracks files in new repos', function()
        screen:try_resize(10, 4)
        setup(config)
        system{"touch", newfile}
        edit(newfile)

        feed("iEDIT<esc>")
        command("write")

        screen:expect{grid=[[
          {3:+ }EDI^T      |
          {6:~           }|
          {6:~           }|
          <5C written |
        ]]}

        -- Stage
        git{"add", newfile}

        screen:expect{grid=[[
          EDI^T        |
          {6:~           }|
          {6:~           }|
          <5C written |
        ]]}

        -- Reset
        git{"reset"}

        screen:expect{grid=[[
          {3:+ }EDI^T      |
          {6:~           }|
          {6:~           }|
          <5C written |
        ]]}

      end)

      it('can detach from buffers', function()
        setup(config)
        edit(test_file)
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

        command('Gitsigns detach')

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

      it('can stages file with merge conflicts', function()
        screen:try_resize(40, 8)
        setup(config)
        command("set signcolumn=yes")

        -- Edit a file and commit it on main branch
        edit(test_file)
        check_status {head='master', added=0, changed=0, removed=0}
        feed('iedit')
        check_status {head='master', added=0, changed=1, removed=0}
        command("write")
        command("bdelete")
        git{'add', test_file}
        git{"commit", "-m", "commit on main"}

        -- Create a branch, remove last commit, edit file again
        git{'checkout', '-B', 'abranch'}
        git{'reset', '--hard', 'HEAD~1'}
        edit(test_file)
        check_status {head='abranch', added=0, changed=0, removed=0}
        feed('idiff')
        check_status {head='abranch', added=0, changed=1, removed=0}
        command("write")
        command("bdelete")
        git{'add', test_file}
        git{"commit", "-m", "commit on branch"}
        git{"rebase", "master"}

        -- test_file should have a conflict
        edit(test_file)
        check_status {head='(rebasing)', added=4, changed=1, removed=0}
        screen:expect{grid=[[
          {2:~ }^<<<<<<< HEAD                          |
          {3:+ }editThis                              |
          {3:+ }=======                               |
          {3:+ }idiffThis                             |
          {3:+ }>>>>>>> {MATCH:.......} (commit on branch)    |
          {1:  }is                                    |
          {1:  }a                                     |
          {7:-- INSERT --}                            |
        ]]}

        exec_lua('require("gitsigns.actions").stage_hunk()')

        check_status {head='(rebasing)', added=0, changed=0, removed=0}
        screen:expect{grid=[[
          {1:  }^<<<<<<< HEAD                          |
          {1:  }editThis                              |
          {1:  }=======                               |
          {1:  }idiffThis                             |
          {1:  }>>>>>>> {MATCH:.......} (commit on branch)    |
          {1:  }is                                    |
          {1:  }a                                     |
          {7:-- INSERT --}                            |
        ]]}

      end)

      it('handle files with spaces', function()
        screen:try_resize(20,6)
        setup(config)
        command("set signcolumn=yes")

        local spacefile = scratch..'/a b c d'

        write_to_file(spacefile, {'spaces', 'in', 'file'})

        edit(spacefile)

        screen:expect{grid=[[
          {3:+ }^spaces            |
          {3:+ }in                |
          {3:+ }file              |
          {6:~                   }|
          {6:~                   }|
                              |
        ]]}

        git{'add', spacefile}
        edit(spacefile)

        screen:expect{grid=[[
          {1:  }^spaces            |
          {1:  }in                |
          {1:  }file              |
          {6:~                   }|
          {6:~                   }|
                              |
        ]]}

      end)
    end
  end

  -- Run regular config
  describe('diff-ext', testsuite(false))

  -- Run with:
  --   - internal diff (ffi)
  --   - decoration provider
  describe('diff-int', testsuite(true))

  -- TODO Add test for current_line_blame
  -- TODO Add test for toggle_current_line_blame

  -- TODO Add test for #163: signcolumn=number with signs disabled shouldn't
  -- overwrite number column

  -- TODO Test config.attach_to_untracked
  -- TODO Add test for #194: Should not attach if file is in a custom git dir

  -- TODO Add test diffthis

end)
