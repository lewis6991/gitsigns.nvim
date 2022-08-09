-- vim: foldnestmax=5 foldminlines=1

local Screen = require('test.functional.ui.screen')
local helpers = require('test.gs_helpers')

local clear           = helpers.clear
local command         = helpers.command
local exec_capture    = helpers.exec_capture
local feed            = helpers.feed
local insert          = helpers.insert
local exec_lua        = helpers.exec_lua
local split           = helpers.split
local get_buf_var     = helpers.curbufmeths.get_var
local fn              = helpers.funcs
local system          = fn.system
local expectf         = helpers.expectf
local write_to_file   = helpers.write_to_file
local edit            = helpers.edit
local cleanup         = helpers.cleanup
local test_file       = helpers.test_file
local git             = helpers.git
local scratch         = helpers.scratch
local newfile         = helpers.newfile
local debug_messages  = helpers.debug_messages
local match_dag       = helpers.match_dag
local match_lines     = helpers.match_lines
local p               = helpers.p
local match_debug_messages = helpers.match_debug_messages
local setup_gitsigns  = helpers.setup_gitsigns
local setup_test_repo = helpers.setup_test_repo
local test_config     = helpers.test_config
local check           = helpers.check
local eq              = helpers.eq

local it = helpers.it(it)

describe('gitsigns', function()
  local screen
  local config

  before_each(function()
    clear()
    screen = Screen.new(20, 17)
    screen:attach({ext_messages=true})

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
      [10] = {foreground = Screen.colors.Red};
    })

    -- Make gitisigns available
    exec_lua('package.path = ...', package.path)
    config = helpers.deepcopy(test_config)
    command('cd '..system{"dirname", os.tmpname()})
  end)

  after_each(function()
    cleanup()
    screen:detach()
  end)

  it('can run basic setup', function()
    setup_gitsigns()
    check { status = {}, signs = {} }
  end)

  it('gitdir watcher works on a fresh repo', function()
    screen:try_resize(20,6)
    setup_test_repo{no_add=true}
    -- Don't set this too low, or else the test will lock up
    config.watch_gitdir = {interval = 100}
    setup_gitsigns(config)
    edit(test_file)

    expectf(function()
      match_dag(debug_messages(), {
        p'run_job: git .* %-%-version',
        'attach(1): Attaching (trigger=BufRead)',
        p'run_job: git .* config user.name',
        p'run_job: git .* rev%-parse %-%-show%-toplevel %-%-absolute%-git%-dir %-%-abbrev%-ref HEAD',
        p('run_job: git .* ls%-files %-%-stage %-%-others %-%-exclude%-standard %-%-eol '..test_file),
        'watch_gitdir(1): Watching git dir',
        p'run_job: git .* show :0:dummy.txt',
        'update(1): updates: 1, jobs: 7'
      })
    end)

    check {
      status = {head='', added=18, changed=0, removed=0},
      signs = {added=8}
    }

    git{"add", test_file}

    check {
      status = {head='', added=0, changed=0, removed=0},
      signs = {}
    }
  end)

  it('can open files not in a git repo', function()
    setup_gitsigns(config)
    command('Gitsigns clear_debug')
    local tmpfile = os.tmpname()
    edit(tmpfile)

    match_debug_messages {
      'attach(1): Attaching (trigger=BufRead)',
      p'run_job: git .* config user.name',
      p'run_job: git .* rev%-parse %-%-show%-toplevel %-%-absolute%-git%-dir %-%-abbrev%-ref HEAD',
      'new: Not in git repo',
      'attach(1): Empty git obj',
    }
    command('Gitsigns clear_debug')

    insert('line')
    command("write")

    match_debug_messages {
      'attach(1): Attaching (trigger=BufWritePost)',
      p'run_job: git .* config user.name',
      p'run_job: git .* rev%-parse %-%-show%-toplevel %-%-absolute%-git%-dir %-%-abbrev%-ref HEAD',
      'new: Not in git repo',
      'attach(1): Empty git obj'
    }
  end)

  describe('when attaching', function()
    before_each(function()
      setup_test_repo()
      setup_gitsigns(config)
    end)

    it('can setup mappings', function()
      edit(test_file)
      expectf(function()
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
      command("Gitsigns clear_debug")
      edit(scratch..'/.git/index')

      match_debug_messages {
        'attach(1): Attaching (trigger=BufRead)',
        'new: In git dir',
        'attach(1): Empty git obj'
      }
    end)

    it('doesn\'t attach to ignored files', function()
      command("Gitsigns clear_debug")
      write_to_file(scratch..'/.gitignore', {'dummy_ignored.txt'})

      local ignored_file = scratch.."/dummy_ignored.txt"

      system{"touch", ignored_file}
      edit(ignored_file)

      match_debug_messages {
        'attach(1): Attaching (trigger=BufRead)',
        p'run_job: git .* config user.name',
        p'run_job: git .* rev%-parse %-%-show%-toplevel %-%-absolute%-git%-dir %-%-abbrev%-ref HEAD',
        p'run_job: git .* ls%-files .*/dummy_ignored.txt',
        'attach(1): Cannot resolve file in repo',
      }

      check {status = {head='master'}}
    end)

    it('doesn\'t attach to non-existent files', function()
      command("Gitsigns clear_debug")
      edit(newfile)

      match_debug_messages {
        'attach(1): Attaching (trigger=BufNewFile)',
        p'run_job: git .* config user.name',
        p'run_job: git .* rev%-parse %-%-show%-toplevel %-%-absolute%-git%-dir %-%-abbrev%-ref HEAD',
        p('run_job: git .* ls%-files %-%-stage %-%-others %-%-exclude%-standard %-%-eol '..newfile),
        'attach(1): Not a file',
      }

      check {status = {head='master'}}
    end)

    it('doesn\'t attach to non-existent files with non-existent sub-dirs', function()
      command("Gitsigns clear_debug")
      edit(scratch..'/does/not/exist')

      match_debug_messages {
        'attach(1): Attaching (trigger=BufNewFile)',
        'attach(1): Not a path',
      }

      helpers.pcall_err(get_buf_var, 'gitsigns_head')
      helpers.pcall_err(get_buf_var, 'gitsigns_status_dict')
    end)

    it('can run copen', function()
      command("Gitsigns clear_debug")
      command("copen")
      match_debug_messages {
        'attach(2): Attaching (trigger=BufRead)',
        'attach(2): Non-normal buffer',
      }
    end)

    it('can run get_hunks()', function()
      edit(test_file)
      insert("line1")
      feed("oline2<esc>")

      expectf(function()
        eq({{
            head = '@@ -1,1 +1,2 @@',
            type = 'change',
            lines = { '-This', '+line1This', '+line2' },
            added   = { count = 2, start = 1, lines = { 'line1This', 'line2' } },
            removed = { count = 1, start = 1, lines = { 'This'} },
          }},
          exec_lua[[return require'gitsigns'.get_hunks()]]
        )
      end)
    end)
  end)

  describe('current line blame', function()
    before_each(function()
      config.current_line_blame = true
      config.current_line_blame_formatter = ' <author>, <author_time:%R> - <summary>'
      setup_gitsigns(config)
    end)

    local function blame_line_ui_test(autocrlf, file_ending)
      setup_test_repo()

      git{'config', 'core.autocrlf', autocrlf}
      if file_ending == 'dos' then
        system("printf 'This\r\nis\r\na\r\nwindows\r\nfile\r\n' > "..newfile)
      else
        system("printf 'This\nis\na\nwindows\nfile\n' > "..newfile)
      end
      git{'add', newfile}
      git{"commit", "-m", "commit on main"}

      edit(newfile)
      feed('gg')
      command("Gitsigns clear_debug")
      check { signs  = {} }

      -- Wait until the virtual blame line appears
      screen:sleep(1000)
      screen:expect{grid=[[
        ^{MATCH:This {6: tester, %d seco}}|
        is                  |
        a                   |
        windows             |
        file                |
        {6:~                   }|
        {6:~                   }|
        {6:~                   }|
        {6:~                   }|
        {6:~                   }|
        {6:~                   }|
        {6:~                   }|
        {6:~                   }|
        {6:~                   }|
        {6:~                   }|
        {6:~                   }|
        {6:~                   }|
      ]]}
    end

    it('doesn\'t error on untracked files', function()
      local nvim_ver = exec_lua('return vim.version().minor')
      if nvim_ver >= 8 then
        pending()
      end

      setup_test_repo{no_add=true}
      edit(newfile)
      insert("line")
      command("write")
      screen:expect{messages = { { content = { { "<" } }, kind = "" } } }
    end)
    --
    it('does handle dos fileformats', function()
      -- Add a file with windows line ending into the repo
      -- Disable autocrlf, so that the file keeps the \r\n file endings.
        blame_line_ui_test('false', 'dos')
    end)

    it('does handle autocrlf', function()
        blame_line_ui_test('true', 'dos')
    end)

    it('does handle unix', function()
        blame_line_ui_test('false', 'unix')
    end)
  end)

  describe('configuration', function()
    it('handled deprecated fields', function()
      config.current_line_blame_delay = 100
      setup_gitsigns(config)
      eq(100, exec_lua([[return package.loaded['gitsigns.config'].config.current_line_blame_opts.delay]]))
    end)
  end)

  describe('on_attach()', function()
    it('can prevent attaching to a buffer', function()
      setup_test_repo{no_add=true}

      -- Functions can't be serialized over rpc so need to setup config
      -- remotely
      setup_gitsigns(config, [[
        config.on_attach = function()
          return false
        end
      ]])
      command("Gitsigns clear_debug")

      edit(test_file)
      match_debug_messages {
        'attach(1): Attaching (trigger=BufRead)',
        p'run_job: git .* config user.name',
        p'run_job: git .* rev%-parse %-%-show%-toplevel %-%-absolute%-git%-dir %-%-abbrev%-ref HEAD',
        p'run_job: git .* rev%-parse %-%-short HEAD',
        p'run_job: git .* %-%-git%-dir .* %-%-stage %-%-others %-%-exclude%-standard %-%-eol.*',
        'attach(1): User on_attach() returned false',
      }
    end)
  end)

  describe('change_base()', function()
    it('works', function()
      setup_test_repo()
      edit(test_file)

      feed('oEDIT<esc>')
      command('write')

      git{'add', test_file}
      git{"commit", "-m", "commit on main"}

      -- Don't setup gitsigns until the repo has two commits
      setup_gitsigns(config)

      check {
        status = {head='master', added=0, changed=0, removed=0},
        signs  = {}
      }

      command('Gitsigns change_base ~')

      check {
        status = {head='master', added=1, changed=0, removed=0},
        signs  = {added=1}
      }
    end)
  end)

  local function testsuite(internal_diff)
    return function()
      before_each(function()
        config.diff_opts = {
          internal = internal_diff
        }
        setup_test_repo()
      end)

      it('apply basic signs', function()
        setup_gitsigns(config)
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

        check {
          status = {head='master', added=1, changed=2, removed=3},
          signs  = {topdelete=1, changedelete=1, added=1, delete=1, changed=1}
        }

      end)

      it('can enable numhl', function()
        config.numhl = true
        setup_gitsigns(config)
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
          {6:~                   }|
        ]]}
      end)

      it('attaches to newly created files', function()
        setup_gitsigns(config)
        command('Gitsigns clear_debug')
        edit(newfile)
        match_debug_messages{
          'attach(1): Attaching (trigger=BufNewFile)',
          p'run_job: git .* config user.name',
          p'run_job: git .* rev%-parse %-%-show%-toplevel %-%-absolute%-git%-dir %-%-abbrev%-ref HEAD',
          p'run_job: git .* ls%-files .*',
          'attach(1): Not a file',
        }
        command('Gitsigns clear_debug')
        command("write")

        local messages = {
          'attach(1): Attaching (trigger=BufWritePost)',
          p"run_job: git .* config user.name",
          p'run_job: git .* rev%-parse %-%-show%-toplevel %-%-absolute%-git%-dir %-%-abbrev%-ref HEAD',
          p'run_job: git .* ls%-files .*',
          'watch_gitdir(1): Watching git dir',
          p'run_job: git .* show :0:newfile.txt'
        }

        if not internal_diff then
          table.insert(messages, p'run_job: git .* diff .* /tmp/lua_.* /tmp/lua_.*')
        end

        local jobs = internal_diff and 9 or 10
        table.insert(messages, "update(1): updates: 1, jobs: "..jobs)

        match_debug_messages(messages)

        check {
          status = {head='master', added=1, changed=0, removed=0},
          signs  = {added=1}
        }

      end)

      it('can add untracked files to the index', function()
        setup_gitsigns(config)

        edit(newfile)
        feed("iline<esc>")
        check{ status = {head='master'}}

        command("write")

        check {
          status = {head='master', added=1, changed=0, removed=0},
          signs  = {added=1}
        }

        feed('mhs') -- Stage the file (add file to index)

        check {
          status = {head='master', added=0, changed=0, removed=0},
          signs  = {}
        }

      end)

      it('tracks files in new repos', function()
        setup_gitsigns(config)
        system{"touch", newfile}
        edit(newfile)

        feed("iEDIT<esc>")
        command("write")

        check {
          status = {head='master', added=1, changed=0, removed=0},
          signs  = {added=1}
        }

        git{"add", newfile}

        check {
          status = {head='master', added=0, changed=0, removed=0},
          signs  = {}
        }

        git{"reset"}

        check {
          status = {head='master', added=1, changed=0, removed=0},
          signs  = {added=1}
        }

      end)

      it('can detach from buffers', function()
        setup_gitsigns(config)
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

        check {
          status = {head='master', added=1, changed=2, removed=3},
          signs  = {topdelete=1, added=1, changed=1, delete=1, changedelete=1}
        }

        command('Gitsigns detach')

        check { status = {}, signs = {} }
      end)

      it('can stages file with merge conflicts', function()
        setup_gitsigns(config)
        command("set signcolumn=yes")

        -- Edit a file and commit it on main branch
        edit(test_file)
        check{ status = {head='master', added=0, changed=0, removed=0} }
        feed('iedit')
        check{ status = {head='master', added=0, changed=1, removed=0} }
        command("write")
        command("bdelete")
        git{'add', test_file}
        git{"commit", "-m", "commit on main"}

        -- Create a branch, remove last commit, edit file again
        git{'checkout', '-B', 'abranch'}
        git{'reset', '--hard', 'HEAD~1'}
        edit(test_file)
        check{ status = {head='abranch', added=0, changed=0, removed=0} }
        feed('idiff')
        check{ status = {head='abranch', added=0, changed=1, removed=0} }
        command("write")
        command("bdelete")
        git{'add', test_file}
        git{"commit", "-m", "commit on branch"}
        git{"rebase", "master"}

        -- test_file should have a conflict
        edit(test_file)
        check {
          status = {head='HEAD(rebasing)', added=4, changed=1, removed=0},
          signs = {changed=1, added=4}
        }

        exec_lua('require("gitsigns.actions").stage_hunk()')

        check {
          status = {head='HEAD(rebasing)', added=0, changed=0, removed=0},
          signs = {}
        }

      end)

      it('handle files with spaces', function()
        setup_gitsigns(config)
        command("set signcolumn=yes")

        local spacefile = scratch..'/a b c d'

        write_to_file(spacefile, {'spaces', 'in', 'file'})

        edit(spacefile)

        check {
          status = {head='master', added=3, removed=0, changed=0},
          signs = {added=3}
        }

        git{'add', spacefile}
        edit(spacefile)

        check {
          status = {head='master', added=0, removed=0, changed=0},
          signs = {}
        }

      end)
    end
  end

  -- Run regular config
  describe('diff-ext', testsuite(false))

  -- Run with:
  --   - internal diff (ffi)
  --   - decoration provider
  describe('diff-int', testsuite(true))

  it('can handle vimgrep', function()
    setup_test_repo()

    write_to_file(scratch..'/t1.txt', {'hello ben'})
    write_to_file(scratch..'/t2.txt', {'hello ben'})
    write_to_file(scratch..'/t3.txt', {'hello lewis'})

    setup_gitsigns(config)
    command('Gitsigns clear_debug')

    helpers.exc_exec("vimgrep ben "..scratch..'/*')

    screen:expect{messages = {{
      kind = "quickfix", content = { { "(1 of 2): hello ben" } },
    }}}

    eq({
      'attach(2): attaching is disabled',
      'attach(3): attaching is disabled',
      'attach(4): attaching is disabled',
      'attach(5): attaching is disabled',
    }, exec_lua[[return require'gitsigns'.debug_messages(true)]])

  end)

  it('show short SHA when detached head', function()
    setup_test_repo()
    git{"checkout", "--detach"}

    -- Disable debug_mode so the sha is calculated
    config.debug_mode = false
    setup_gitsigns(config)
    edit(test_file)

    -- SHA is not deterministic so just check it can be cast as a hex value
    expectf(function()
      helpers.neq(nil, tonumber('0x'..get_buf_var('gitsigns_head')))
    end)
  end)

  it('handles a quick undo', function()
    setup_test_repo()
    setup_gitsigns(config)
    edit(test_file)
    -- This test isn't deterministic so run it a few times
    for _ = 1, 3 do
      feed("x")
      check { signs = {changed=1} }
      feed("u")
      check { signs = {} }
    end
  end)

  it('handles filenames with unicode characters', function()
    screen:try_resize(20,2)
    setup_test_repo()
    setup_gitsigns(config)
    local uni_filename = scratch..'/föobær'

    write_to_file(uni_filename, {'Lorem ipsum'})
    git{"add", uni_filename}
    git{"commit", "-m", "another commit"}

    edit(uni_filename)

    screen:expect{grid=[[
      ^Lorem ipsum         |
      {6:~                   }|
    ]]}

    feed 'x'

    screen:expect{grid=[[
      {2:~ }^orem ipsum        |
      {6:~                   }|
    ]]}
  end)

  it('handle #521', function()
    screen:detach()
    screen:attach({ext_messages=false})
    screen:try_resize(20,3)
    setup_test_repo()
    setup_gitsigns(config)
    edit(test_file)
    feed('dd')

    local function check_screen()
      screen:expect{grid=[[
        {4:^ }^is                |
        {1:  }a                 |
        {1:  }file              |
      ]]}
    end

    check_screen()

    -- Write over the text with itself. This will remove all the signs but the
    -- calculated hunks won't change.
    exec_lua[[
      local text = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      vim.api.nvim_buf_set_lines(0, 0, -1, true, text)
    ]]

    check_screen()

  end)

end)
