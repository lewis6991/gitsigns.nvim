local Screen = require('nvim-test.screen')
local helpers = require('test.gs_helpers')

local api = helpers.api
local check = helpers.check
local cleanup = helpers.cleanup
local clear = helpers.clear
local command = api.nvim_command
local edit = helpers.edit
local eq = helpers.eq
local exec_lua = helpers.exec_lua
local expectf = helpers.expectf
local feed = helpers.feed
local fn = helpers.fn
local get_buf_var = api.nvim_buf_get_var
local git = helpers.git
local insert = helpers.insert
local match_dag = helpers.match_dag
local match_debug_messages = helpers.match_debug_messages
local match_lines = helpers.match_lines
local n, p, np = helpers.n, helpers.p, helpers.np
local newfile = helpers.newfile
local scratch = helpers.scratch
local setup_gitsigns = helpers.setup_gitsigns
local setup_test_repo = helpers.setup_test_repo
local split = vim.split
local system = fn.system
local test_config = helpers.test_config
local test_file = helpers.test_file
local write_to_file = helpers.write_to_file

helpers.env()

---@param bufnr? integer
local function wait_for_attach(bufnr)
  expectf(function()
    return exec_lua(function(bufnr0)
      return vim.b[bufnr0 or 0].gitsigns_status_dict.gitdir ~= nil
    end, bufnr)
  end)
  match_debug_messages({
    ('attach(1): attach complete'):format(bufnr or api.nvim_get_current_buf()),
  })
end

local revparse_pat = ('run_job: git .* rev-parse --show-toplevel --absolute-git-dir --abbrev-ref HEAD'):gsub(
  '%-',
  '%%-'
)

describe('gitsigns (with screen)', function()
  local screen --- @type test.screen
  local config --- @type table

  before_each(function()
    clear()
    screen = Screen.new(20, 17)
    screen:attach({ ext_messages = true })

    local default_attrs = {
      [1] = { foreground = Screen.colors.DarkBlue, background = Screen.colors.WebGray },
      [2] = { foreground = Screen.colors.DodgerBlue },
      [3] = { foreground = Screen.colors.SeaGreen },
      [4] = { foreground = Screen.colors.Red },
      [5] = { foreground = Screen.colors.Brown },
      [6] = { foreground = Screen.colors.Blue1, bold = true },
      [7] = { bold = true },
      [8] = { foreground = Screen.colors.White, background = Screen.colors.Red },
      [9] = { foreground = Screen.colors.SeaGreen, bold = true },
      [11] = { foreground = Screen.colors.Red1, background = Screen.colors.WebGray },
      [12] = { foreground = Screen.colors.DodgerBlue, background = Screen.colors.WebGray },
    }

    -- Use the classic vim colorscheme, not the new defaults in nvim >= 0.10
    if fn.has('nvim-0.12') == 0 then
      default_attrs[2].foreground = Screen.colors.NvimDarkCyan
      default_attrs[3].foreground = Screen.colors.NvimDarkGreen
      default_attrs[4].foreground = Screen.colors.NvimDarkRed
      default_attrs[11].foreground = Screen.colors.NvimDarkRed
      default_attrs[12] =
        { foreground = Screen.colors.NvimDarkCyan, background = Screen.colors.Gray }
    end

    command('colorscheme vim')

    screen:set_default_attr_ids(default_attrs)

    config = vim.deepcopy(test_config)
    command('cd ' .. system({ 'dirname', os.tmpname() }))
  end)

  after_each(function()
    cleanup()
    screen:detach()
  end)

  it('can run basic setup', function()
    setup_gitsigns()
    check({ status = {}, signs = {} })
  end)

  it('gitdir watcher works on a fresh repo', function()
    --- @type integer
    local nvim_ver = exec_lua('return vim.version().minor')
    screen:try_resize(20, 6)
    setup_test_repo({ no_add = true })
    -- Don't set this too low, or else the test will lock up
    config.watch_gitdir = { interval = 100 }
    setup_gitsigns(config)
    edit(test_file)

    match_dag({
      'attach(1): Attaching (trigger=BufReadPost)',
      p('run_job: git .* config user.name'),
      p(revparse_pat),
      p(
        'run_job: git .* ls%-files %-%-stage %-%-others %-%-exclude%-standard %-%-eol '
          .. vim.pesc(test_file)
      ),
      'attach(1): Watching git dir',
    })

    check({
      status = { head = '', added = 18, changed = 0, removed = 0 },
      signs = { untracked = nvim_ver == 9 and 8 or 7 },
    })

    git('add', test_file)

    check({
      status = { head = '', added = 0, changed = 0, removed = 0 },
      signs = {},
    })
  end)

  it('can open files not in a git repo', function()
    setup_gitsigns(config)
    local tmpfile = os.tmpname()
    edit(tmpfile)

    match_debug_messages({
      'attach(1): Attaching (trigger=BufReadPost)',
      np(revparse_pat),
      n('new: Not in git repo'),
      n('attach(1): Empty git obj'),
    })
    command('Gitsigns clear_debug')

    insert('line')
    command('write')

    match_debug_messages({
      n('attach(1): Attaching (trigger=BufWritePost)'),
      np(revparse_pat),
      n('new: Not in git repo'),
      n('attach(1): Empty git obj'),
    })
  end)

  describe('when attaching', function()
    before_each(function()
      setup_test_repo()
      setup_gitsigns(config)
    end)

    it('can setup mappings', function()
      edit(test_file)
      expectf(function()
        local res = split(api.nvim_exec2('nmap <buffer>', { output = true }).output, '\n')
        table.sort(res)

        -- Check all keymaps get set
        match_lines(res, {
          n('n  mhS         *@<Cmd>lua require"gitsigns".stage_buffer()<CR>'),
          n('n  mhU         *@<Cmd>lua require"gitsigns".reset_buffer_index()<CR>'),
          n('n  mhp         *@<Cmd>lua require"gitsigns".preview_hunk()<CR>'),
          n('n  mhr         *@<Cmd>lua require"gitsigns".reset_hunk()<CR>'),
          n('n  mhs         *@<Cmd>lua require"gitsigns".stage_hunk()<CR>'),
          n('n  mhu         *@<Cmd>lua require"gitsigns".undo_stage_hunk()<CR>'),
        })
      end)
    end)

    it('does not attach inside .git', function()
      edit(scratch .. '/.git/index')

      match_debug_messages({
        'attach(1): Attaching (trigger=BufReadPost)',
        n('run_job: git --version'),
        p(revparse_pat),
        n('new: Not in git repo'),
        n('attach(1): Empty git obj'),
      })
    end)

    it("doesn't attach to ignored files", function()
      write_to_file(scratch .. '/.gitignore', { 'dummy_ignored.txt' })

      local ignored_file = scratch .. '/dummy_ignored.txt'

      system({ 'touch', ignored_file })
      edit(ignored_file)

      match_debug_messages({
        'attach(1): Attaching (trigger=BufReadPost)',
        np(revparse_pat),
        np('run_job: git .* config user.name'),
        np('run_job: git .* ls%-files .*/dummy_ignored.txt'),
        n('attach(1): Cannot resolve file in repo'),
      })

      check({ status = { head = 'main' } })
    end)

    it("doesn't attach to non-existent files", function()
      edit(newfile)

      match_debug_messages({
        'attach(1): Attaching (trigger=BufNewFile)',
        np(revparse_pat),
        np('run_job: git .* config user.name'),
        np(
          'run_job: git .* ls%-files %-%-stage %-%-others %-%-exclude%-standard %-%-eol '
            .. vim.pesc(newfile)
        ),
        'attach(1): Cannot resolve file in repo',
      })

      check({ status = { head = 'main' } })
    end)

    it("doesn't attach to non-existent files with non-existent sub-dirs", function()
      edit(scratch .. '/does/not/exist')

      match_debug_messages({
        'attach(1): Attaching (trigger=BufNewFile)',
        n('attach(1): Not a path'),
      })

      helpers.pcall_err(get_buf_var, 0, 'gitsigns_head')
      helpers.pcall_err(get_buf_var, 0, 'gitsigns_status_dict')
    end)

    it('can run copen', function()
      command('copen')
      match_debug_messages({
        'attach(2): Attaching (trigger=BufReadPost)',
        n('attach(2): Non-normal buffer'),
      })
    end)

    it('can run get_hunks()', function()
      edit(test_file)
      insert('line1')
      feed('oline2<esc>')

      expectf(function()
        eq({
          {
            head = '@@ -1,1 +1,2 @@',
            type = 'change',
            lines = { '-This', '+line1This', '+line2' },
            added = { count = 2, start = 1, lines = { 'line1This', 'line2' } },
            removed = { count = 1, start = 1, lines = { 'This' } },
          },
        }, exec_lua([[return require'gitsigns'.get_hunks()]]))
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
      exec_lua([[vim.g.editorconfig = false]])

      git('config', 'core.autocrlf', autocrlf)
      if file_ending == 'dos' then
        system("printf 'This\r\nis\r\na\r\nwindows\r\nfile\r\n' > " .. newfile)
      else
        system("printf 'This\nis\na\nwindows\nfile\n' > " .. newfile)
      end

      git('add', newfile)
      git('commit', '-m', 'commit on main')

      edit(newfile)
      feed('gg')
      check({ signs = {} })

      screen:expect({
        grid = [[
        ^{MATCH:This {6: You, %d second.}}|
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
      ]],
      })
    end

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

  describe('falls back from right_align to eol when text is too long  (#1322)', function()
    before_each(function()
      setup_test_repo({
        test_file_text = {
          'short',
          string.rep('a', 25),
          string.rep('b', 40),
        },
      })

      config.current_line_blame = true
      config.current_line_blame_formatter = ' <author>, <author_time:%R> - <summary>'
      config.current_line_blame_opts = { virt_text_pos = 'right_align' }
      setup_gitsigns(config)
    end)

    it('with nowrap', function()
      edit(test_file)
      command('set nowrap')
      feed('gg')

      screen:expect({
        grid = [[
        ^short {MATCH:{6: You, %d+ second}}|
        aaaaaaaaaaaaaaaaaaaa|
        bbbbbbbbbbbbbbbbbbbb|
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
        {6:~                   }|
        {6:~                   }|
      ]],
      })

      -- Medium line: blame should fallback to eol (no space for right_align)
      feed('j')
      screen:expect({
        grid = [[
        short               |
        ^aaaaaaaaaaaaaaaaaaaa|
        bbbbbbbbbbbbbbbbbbbb|
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
        {6:~                   }|
        {6:~                   }|
      ]],
      })

      -- Move to very long line
      feed('j')
      screen:expect({
        grid = [[
        short               |
        aaaaaaaaaaaaaaaaaaaa|
        ^bbbbbbbbbbbbbbbbbbbb|
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
        {6:~                   }|
        {6:~                   }|
      ]],
      })
    end)

    it('with wrap', function()
      edit(test_file)
      command('set wrap')
      feed('gg')

      -- Short line: blame should appear with right_align (normal behavior)
      screen:expect({
        grid = [[
        ^short {MATCH:{6: You, %d+ second}}|
        aaaaaaaaaaaaaaaaaaaa|
        aaaaa               |
        bbbbbbbbbbbbbbbbbbbb|
        bbbbbbbbbbbbbbbbbbbb|
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
      ]],
      })

      -- Move to medium line (will wrap and blame appears at end of wrapped line)
      feed('j')
      screen:expect({
        grid = [[
        short               |
        ^aaaaaaaaaaaaaaaaaaaa|
        {MATCH:aaaaa {6: You, %d second.*}}|
        bbbbbbbbbbbbbbbbbbbb|
        bbbbbbbbbbbbbbbbbbbb|
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
      ]],
      })

      -- Move to very long line (wraps across multiple lines, no blame visible)
      feed('j')
      screen:expect({
        grid = [[
        short               |
        aaaaaaaaaaaaaaaaaaaa|
        aaaaa               |
        ^bbbbbbbbbbbbbbbbbbbb|
        bbbbbbbbbbbbbbbbbbbb|
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
      ]],
      })
    end)
  end)

  --  TODO(lewis6991): All deprecated fields removed. Re-add when we have another deprecated field
  -- describe('configuration', function()
  --   it('handled deprecated fields', function()
  --     pending()
  --     -- config.current_line_blame_delay = 100
  --     -- setup_gitsigns(config)
  --     -- eq(100, exec_lua([[return package.loaded['gitsigns.config'].config.current_line_blame_opts.delay]]))
  --   end)
  -- end)

  describe('on_attach()', function()
    it('can prevent attaching to a buffer', function()
      setup_test_repo({ no_add = true })
      setup_gitsigns(config, true)

      edit(test_file)
      match_debug_messages({
        'attach(1): Attaching (trigger=BufReadPost)',
        np(revparse_pat),
        np('run_job: git .* rev%-parse %-%-short HEAD'),
        np('run_job: git .* config user.name'),
        np('run_job: git .* %-%-git%-dir .* %-%-stage %-%-others %-%-exclude%-standard %-%-eol.*'),
        n('attach(1): User on_attach() returned false'),
      })
    end)
  end)

  describe('change_base()', function()
    it('works', function()
      setup_test_repo()
      edit(test_file)

      feed('oEDIT<esc>')
      command('write')

      git('add', test_file)
      git('commit', '-m', 'commit on main')

      -- Don't setup gitsigns until the repo has two commits
      setup_gitsigns(config)

      check({
        status = { head = 'main', added = 0, changed = 0, removed = 0 },
        signs = {},
      })

      command('Gitsigns change_base ~')

      check({
        status = { head = 'main', added = 1, changed = 0, removed = 0 },
        signs = { added = 1 },
      })
    end)
  end)

  local function testsuite(internal_diff)
    return function()
      before_each(function()
        config.diff_opts = {
          internal = internal_diff,
        }
        setup_test_repo()
      end)

      it('apply basic signs', function()
        setup_gitsigns(config)
        edit(test_file)
        command('set signcolumn=yes')

        feed('dd') -- Top delete
        feed('j')
        feed('o<esc>') -- Add
        feed('2j')
        feed('x') -- Change
        feed('3j')
        feed('dd') -- Delete
        feed('j')
        feed('ddx') -- Change delete

        check({
          status = { head = 'main', added = 1, changed = 2, removed = 3 },
          signs = { topdelete = 1, changedelete = 1, added = 1, delete = 1, changed = 1 },
        })
      end)

      it('can enable numhl', function()
        config.numhl = true
        setup_gitsigns(config)
        edit(test_file)
        command('set signcolumn=no')
        command('set number')

        feed('dd') -- Top delete
        feed('j')
        feed('o<esc>') -- Add
        feed('2j')
        feed('x') -- Change
        feed('3j')
        feed('dd') -- Delete
        feed('j')
        feed('ddx') -- Change delete

        -- screen:snapshot_util()
        screen:expect({
          grid = [[
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
        ]],
        })
      end)

      it('attaches to newly created files', function()
        setup_gitsigns(config)
        edit(newfile)
        match_debug_messages({
          'attach(1): Attaching (trigger=BufNewFile)',
          np(revparse_pat),
          np('run_job: git .* config user.name'),
          np('run_job: git .* ls%-files .*'),
          n('attach(1): Cannot resolve file in repo'),
        })
        command('write')

        local messages = {
          'attach(1): Attaching (trigger=BufWritePost)',
          np(revparse_pat),
          np('run_job: git .* ls%-files .*'),
          n('attach(1): Watching git dir'),
        }

        if not internal_diff then
          table.insert(messages, np('run_job: git .* diff .* /.* /.*'))
        end

        match_debug_messages(messages)

        check({
          status = { head = 'main', added = 1, changed = 0, removed = 0 },
          signs = { untracked = 1 },
        })
      end)

      it('can add untracked files to the index', function()
        setup_gitsigns(config)

        edit(newfile)
        feed('iline<esc>')
        check({ status = { head = 'main' } })

        command('write')

        check({
          status = { head = 'main', added = 1, changed = 0, removed = 0 },
          signs = { untracked = 1 },
        })

        feed('mhs') -- Stage the file (add file to index)

        check({
          status = { head = 'main', added = 0, changed = 0, removed = 0 },
          signs = {},
        })
      end)

      it('tracks files in new repos', function()
        setup_gitsigns(config)
        system({ 'touch', newfile })
        edit(newfile)

        feed('iEDIT<esc>')
        command('write')

        check({
          status = { head = 'main', added = 1, changed = 0, removed = 0 },
          signs = { untracked = 1 },
        })

        git('add', newfile)

        check({
          status = { head = 'main', added = 0, changed = 0, removed = 0 },
          signs = {},
        })

        git('reset')

        check({
          status = { head = 'main', added = 1, changed = 0, removed = 0 },
          signs = { untracked = 1 },
        })
      end)

      it('can detach from buffers', function()
        setup_gitsigns(config)
        edit(test_file)
        command('set signcolumn=yes')

        feed('dd') -- Top delete
        feed('j')
        feed('o<esc>') -- Add
        feed('2j')
        feed('x') -- Change
        feed('3j')
        feed('dd') -- Delete
        feed('j')
        feed('ddx') -- Change delete

        check({
          status = { head = 'main', added = 1, changed = 2, removed = 3 },
          signs = { topdelete = 1, added = 1, changed = 1, delete = 1, changedelete = 1 },
        })

        command('Gitsigns detach')

        check({ status = {}, signs = {} })
      end)

      it('can stages file with merge conflicts', function()
        setup_gitsigns(config)
        command('set signcolumn=yes')

        -- Edit a file and commit it on main branch
        edit(test_file)
        check({ status = { head = 'main', added = 0, changed = 0, removed = 0 } })
        feed('iedit')
        check({ status = { head = 'main', added = 0, changed = 1, removed = 0 } })
        command('write')
        command('bwipe')

        git('add', test_file)
        git('commit', '-m', 'commit on main')

        -- Create a branch, remove last commit, edit file again
        git('checkout', '-B', 'abranch')
        git('reset', '--hard', 'HEAD~1')

        edit(test_file)
        check({ status = { head = 'abranch', added = 0, changed = 0, removed = 0 } })
        feed('idiff')
        check({ status = { head = 'abranch', added = 0, changed = 1, removed = 0 } })
        command('write')
        command('bwipe')

        git('add', test_file)
        git('commit', '-m', 'commit on branch')
        git('rebase', 'main')

        -- test_file should have a conflict
        edit(test_file)
        check({
          status = { head = 'HEAD(rebasing)', added = 4, changed = 1, removed = 0 },
          signs = { changed = 1, added = 4 },
        })

        -- Minor delay to avoid the test being flaky
        helpers.sleep(50)

        exec_lua(function()
          require('gitsigns.actions').stage_hunk()
        end)

        check({
          status = { head = 'HEAD(rebasing)', added = 0, changed = 0, removed = 0 },
          signs = {},
        })
      end)

      it('handle files with spaces', function()
        setup_gitsigns(config)
        command('set signcolumn=yes')

        local spacefile = scratch .. '/a b c d'

        write_to_file(spacefile, { 'spaces', 'in', 'file' })

        edit(spacefile)

        check({
          status = { head = 'main', added = 3, removed = 0, changed = 0 },
          signs = { untracked = 3 },
        })

        git('add', spacefile)
        edit(spacefile)

        check({
          status = { head = 'main', added = 0, removed = 0, changed = 0 },
          signs = {},
        })
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

    write_to_file(scratch .. '/t1.txt', { 'hello ben' })
    write_to_file(scratch .. '/t2.txt', { 'hello ben' })
    write_to_file(scratch .. '/t3.txt', { 'hello lewis' })

    setup_gitsigns(config)

    helpers.exc_exec('vimgrep ben ' .. scratch .. '/*')

    if fn.has('nvim-0.12') > 0 then
      screen:expect({
        messages = {
          {
            kind = '',
            content = { { scratch .. '/dummy.txt' } },
          },
          {
            kind = 'quickfix',
            content = { { '(1 of 2): hello ben' } },
          },
        },
      })
    else
      screen:expect({
        messages = {
          {
            kind = 'quickfix',
            content = { { '(1 of 2): hello ben' } },
          },
        },
      })
    end

    match_debug_messages({
      'attach_autocmd(2): Attaching is disabled',
      n('attach_autocmd(3): Attaching is disabled'),
      n('attach_autocmd(4): Attaching is disabled'),
      n('attach_autocmd(5): Attaching is disabled'),
    })
  end)

  it('show short SHA when detached head', function()
    setup_test_repo()
    git('checkout', '--detach')

    -- Disable debug_mode so the sha is calculated
    config.debug_mode = false
    setup_gitsigns(config)
    edit(test_file)

    -- SHA is not deterministic so just check it can be cast as a hex value
    expectf(function()
      helpers.neq(nil, tonumber('0x' .. get_buf_var(0, 'gitsigns_head')))
    end)
  end)

  it('handles a quick undo', function()
    setup_test_repo()
    setup_gitsigns(config)
    edit(test_file)
    -- This test isn't deterministic so run it a few times
    for _ = 1, 3 do
      feed('x')
      check({ signs = { changed = 1 } })
      feed('u')
      check({ signs = {} })
    end
  end)

  it('handles filenames with unicode characters', function()
    screen:try_resize(20, 2)
    setup_test_repo()
    setup_gitsigns(config)
    local uni_filename = scratch .. '/föobær'

    write_to_file(uni_filename, { 'Lorem ipsum' })

    git('add', uni_filename)
    git('commit', '-m', 'another commit')

    edit(uni_filename)

    screen:expect({ grid = [[
      ^Lorem ipsum         |
      {6:~                   }|
    ]] })

    feed('x')

    if fn.has('nvim-0.11') > 0 then
      screen:expect({
        grid = [[
        {12:~ }^orem ipsum        |
        {6:~                   }|
        ]],
      })
    else
      screen:expect({
        grid = [[
        {2:~ }^orem ipsum        |
        {6:~                   }|
        ]],
      })
    end
  end)

  it('handle #521', function()
    screen:detach()
    screen:attach()
    screen:try_resize(20, 4)
    setup_test_repo()
    setup_gitsigns(config)
    edit(test_file)
    feed('dd')

    local function check_screen(unchanged)
      if fn.has('nvim-0.11') > 0 then
        -- TODO(lewis6991): ???
        screen:expect({
          grid = [[
          {11:^ }^is                |
          {1:  }a                 |
          {1:  }file              |
                              |
        ]],
          unchanged = unchanged,
        })
      else
        screen:expect({
          grid = [[
          {4:^ }^is                |
          {1:  }a                 |
          {1:  }file              |
          {1:  }used              |
        ]],
          unchanged = unchanged,
        })
      end
    end

    check_screen()

    -- Write over the text with itself. This will remove all the signs but the
    -- calculated hunks won't change.
    exec_lua(function()
      local text = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      vim.api.nvim_buf_set_lines(0, 0, -1, true, text)
    end)

    check_screen(true)
  end)

  it('shows "No newline at end of file" in preview popup', function()
    setup_test_repo({ test_file_text = { 'a' } })
    setup_gitsigns(config)
    screen:try_resize(30, 10)
    edit(test_file)
    wait_for_attach()

    -- Remove newline at end of file (`printf a >a`)
    local file_path = scratch .. '/dummy.txt'
    local f = assert(io.open(file_path, 'wb'))
    f:write('a') -- Write without trailing newline
    f:close()

    command('checktime')
    helpers.sleep(50)
    feed('mhp')
    screen:expect({ any = [[No newline at end of file]] })
  end)
end)

describe('gitsigns attach', function()
  local config --- @type table

  before_each(function()
    clear()
    config = vim.deepcopy(test_config)
    command('cd ' .. system({ 'dirname', os.tmpname() }))
  end)

  after_each(function()
    cleanup()
  end)

  it('handle #888', function()
    setup_test_repo()

    local path1 = scratch .. '/cargo.toml'
    local subdir = scratch .. '/subdir'
    local path2 = subdir .. '/cargo.toml'

    write_to_file(path1, { 'some text' })
    git('add', path1)
    git('commit', '-m', 'add cargo')

    -- move file and stage move
    system({ 'mkdir', subdir })
    system({ 'mv', path1, path2 })
    git('add', path1, path2)

    config.base = 'HEAD'
    setup_gitsigns(config)
    edit(path1)
    command('write')
    helpers.sleep(100)
  end)

  it('does not error on non-file fugitive buffers (#1277)', function()
    -- Note this test is testing the attach logic before the git_obj
    -- is created.

    setup_gitsigns(config)

    -- Since this bufname isn't a valid path, Nvim will not trigger the
    -- BufNewFile autocmd, therefore we need to manually attach.
    edit(('fugitive://%s/.git//'):format(scratch))
    command('Gitsigns attach')
    match_debug_messages({
      'attach(1): Empty git obj',
    })
  end)

  it('can run diffthis/show when cwd is a subdir of a git repo (#1277)', function()
    helpers.git_init_scratch()
    local file = scratch .. '/sub/test'
    system({ 'mkdir', vim.fs.dirname(file) })
    write_to_file(file, { 'hello' })
    git('add', file)
    git('commit', '-m', 'commit 1')
    command('cd ' .. vim.fs.dirname(file))

    setup_gitsigns(config)

    edit('test')
    wait_for_attach()

    command('Gitsigns show')
    wait_for_attach()

    eq('gitsigns://' .. scratch .. '/.git//:0:sub/test', api.nvim_buf_get_name(0))

    local gfile, toplevel, gitdir, abbrev_head = exec_lua(function()
      local git_obj = assert(require('gitsigns.cache').cache[1]).git_obj
      return git_obj.file, git_obj.repo.toplevel, git_obj.repo.gitdir, git_obj.repo.abbrev_head
    end)

    eq(file, gfile)
    eq(scratch, toplevel)
    eq(scratch .. '/.git', gitdir)
    eq('main', abbrev_head)
  end)

  it('does not error when attaching to files out of tree (#1297)', function()
    setup_test_repo()
    setup_gitsigns(config)

    exec_lua(function(scratch0)
      vim.env.GIT_DIR = scratch0 .. '/.git'
      vim.env.GIT_WORK_TREE = scratch0
    end, scratch)

    edit(fn.tempname())

    match_debug_messages({
      p("get_info: '.*' is outside worktree '.*'"),
      'attach(1): Empty git obj',
    })
  end)
end)
