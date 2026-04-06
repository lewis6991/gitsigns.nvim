local Screen = require('nvim-test.screen')
local helpers = require('test.gs_helpers')

local api = helpers.api
local check = helpers.check
local cleanup = helpers.cleanup
local clear = helpers.clear
local command = api.nvim_command
local command_wait_gitsigns_update = helpers.command_wait_gitsigns_update
local edit = helpers.edit
local eq = helpers.eq
local eq_path = helpers.eq_path
local exec_lua = helpers.exec_lua
local expectf = helpers.expectf
local feed = helpers.feed
local get_buf_var = api.nvim_buf_get_var
local git = helpers.git
local insert = helpers.insert
local match_dag = helpers.match_dag
local match_debug_messages = helpers.match_debug_messages
local match_lines = helpers.match_lines
local n, p, np = helpers.n, helpers.p, helpers.np
local path_pattern = helpers.path_pattern
local setup_gitsigns = helpers.setup_gitsigns
local setup_test_repo = helpers.setup_test_repo
local split = vim.split
local test_config = helpers.test_config
local wait_for_attach = helpers.wait_for_attach
local write_to_file = helpers.write_to_file
local fn = helpers.fn
local newfile --- @type string
local scratch --- @type string
local test_file --- @type string

helpers.env()

local function refresh_paths()
  newfile = helpers.newfile
  scratch = helpers.scratch
  test_file = helpers.test_file
end

local revparse_pat = ('system.system: git .* rev-parse --show-toplevel --absolute-git-dir --abbrev-ref HEAD'):gsub(
  '%-',
  '%%-'
)
local attach_open_pat = 'attach%.attach%(1%): Attaching %(trigger=Buf%u%l+%u%l+%)'

describe('gitsigns (with screen)', function()
  local screen --- @type test.screen
  local config --- @type table

  before_each(function()
    clear()
    refresh_paths()
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
    helpers.chdir_tmp()
  end)

  after_each(function()
    cleanup()
    screen:detach()
  end)

  it('can run basic setup', function()
    setup_gitsigns(config)
    check({ status = {}, signs = {} })
  end)

  it('gitdir watcher works on a fresh repo', function()
    --- @type integer
    local nvim_ver = exec_lua('return vim.version().minor')
    screen:try_resize(20, 6)
    setup_test_repo({ no_add = true })
    config.watch_gitdir.enable = true
    setup_gitsigns(config)
    edit(test_file)

    match_dag({
      'attach.attach(1): Attaching (trigger=BufReadPost)',
      p('system.system: git .* config user.name'),
      p(revparse_pat),
      p(
        'system.system: git .* ls%-files %-%-stage %-%-others %-%-exclude%-standard %-%-eol '
          .. path_pattern(test_file)
      ),
      p('attach%.attach%(1%): Watching git dir .*'),
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
    local tmpfile = helpers.tempname()
    edit(tmpfile)

    match_debug_messages({
      p(attach_open_pat),
      np(revparse_pat),
      np('Not in git repo'),
      np('Empty git obj'),
    })
    command('Gitsigns clear_debug')

    insert('line')
    command('write')

    match_debug_messages({
      n('attach.attach(1): Attaching (trigger=BufWritePost)'),
      np(revparse_pat),
      n('git.new: Not in git repo'),
      n('attach.attach(1): Empty git obj'),
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
        'attach.attach(1): Attaching (trigger=BufReadPost)',
        n('system.system: git --version'),
        p(revparse_pat),
        n('git.new: Not in git repo'),
        n('attach.attach(1): Empty git obj'),
      })
    end)

    it("doesn't attach to ignored files", function()
      write_to_file(scratch .. '/.gitignore', { 'dummy_ignored.txt' })

      local ignored_file = scratch .. '/dummy_ignored.txt'

      helpers.touch(ignored_file)
      edit(ignored_file)

      match_debug_messages({
        'attach.attach(1): Attaching (trigger=BufReadPost)',
        np(revparse_pat),
        np('system.system: git .* config user.name'),
        np('system.system: git .* ls%-files ' .. path_pattern(ignored_file)),
        n('attach.attach(1): Cannot resolve file in repo'),
      })

      check({ status = { head = 'main' } })
    end)

    it('does not attach to nodiff files', function()
      write_to_file(scratch .. '/.gitattributes', { '*.bar -diff' })

      local nodiff_file = scratch .. '/dummy.bar'
      write_to_file(nodiff_file, { 'dummy' })

      git('add', scratch .. '/.gitattributes', nodiff_file)
      git('commit', '-m', 'add nodiff file')

      edit(nodiff_file)

      match_debug_messages({
        'attach.attach(1): Attaching (trigger=BufReadPost)',
        np(revparse_pat),
        np('attach%.attach%(1%): File has %-diff attribute'),
      })

      check({ status = { head = 'main' }, signs = {} })
    end)

    it('requires --force to manually attach to nodiff files from the command line', function()
      write_to_file(scratch .. '/.gitattributes', { '*.bar -diff' })

      local nodiff_file = scratch .. '/dummy.bar'
      write_to_file(nodiff_file, { 'dummy' })

      git('add', scratch .. '/.gitattributes', nodiff_file)
      git('commit', '-m', 'add nodiff file')

      edit(nodiff_file)

      match_debug_messages({
        'attach.attach(1): Attaching (trigger=BufReadPost)',
        np(revparse_pat),
        np('attach%.attach%(1%): File has %-diff attribute'),
      })

      command('Gitsigns attach')

      match_debug_messages({
        'attach.attach(1): Attaching (trigger=BufReadPost)',
        np(revparse_pat),
        np('attach%.attach%(1%): File has %-diff attribute'),
        'attach.attach(1): Attaching (trigger=command)',
        np(revparse_pat),
        np('attach%.attach%(1%): File has %-diff attribute'),
      })

      check({ status = { head = 'main' }, signs = {} })

      command('Gitsigns attach --force')

      wait_for_attach()
      check({ status = { head = 'main', added = 0, changed = 0, removed = 0 }, signs = {} })
    end)

    it('can manually attach to nodiff files via attach({ force = true })', function()
      write_to_file(scratch .. '/.gitattributes', { '*.bar -diff' })

      local nodiff_file = scratch .. '/dummy.bar'
      write_to_file(nodiff_file, { 'dummy' })

      git('add', scratch .. '/.gitattributes', nodiff_file)
      git('commit', '-m', 'add nodiff file')

      edit(nodiff_file)

      match_debug_messages({
        'attach.attach(1): Attaching (trigger=BufReadPost)',
        np(revparse_pat),
        np('attach%.attach%(1%): File has %-diff attribute'),
      })

      exec_lua([[require('gitsigns').attach({ force = true })]])

      wait_for_attach()
      check({ status = { head = 'main', added = 0, changed = 0, removed = 0 }, signs = {} })
    end)

    it('can manually attach to nodiff files with force and a custom trigger', function()
      write_to_file(scratch .. '/.gitattributes', { '*.bar -diff' })

      local nodiff_file = scratch .. '/dummy.bar'
      write_to_file(nodiff_file, { 'dummy' })

      git('add', scratch .. '/.gitattributes', nodiff_file)
      git('commit', '-m', 'add nodiff file')

      edit(nodiff_file)

      match_debug_messages({
        'attach.attach(1): Attaching (trigger=BufReadPost)',
        np(revparse_pat),
        np('attach%.attach%(1%): File has %-diff attribute'),
      })

      exec_lua([=[
        require('gitsigns').attach({
          bufnr = vim.api.nvim_get_current_buf(),
          trigger = 'test',
          force = true,
        })
      ]=])

      wait_for_attach()
      check({ status = { head = 'main', added = 0, changed = 0, removed = 0 }, signs = {} })
    end)

    it('can manually attach to nodiff files with an explicit bufnr in opts', function()
      write_to_file(scratch .. '/.gitattributes', { '*.bar -diff' })

      local nodiff_file = scratch .. '/dummy.bar'
      write_to_file(nodiff_file, { 'dummy' })

      git('add', scratch .. '/.gitattributes', nodiff_file)
      git('commit', '-m', 'add nodiff file')

      edit(nodiff_file)

      match_debug_messages({
        'attach.attach(1): Attaching (trigger=BufReadPost)',
        np(revparse_pat),
        np('attach%.attach%(1%): File has %-diff attribute'),
      })

      exec_lua(
        [[require('gitsigns').attach({ bufnr = vim.api.nvim_get_current_buf(), force = true })]]
      )

      wait_for_attach()
      check({ status = { head = 'main', added = 0, changed = 0, removed = 0 }, signs = {} })
    end)

    it("doesn't attach to non-existent files", function()
      edit(newfile)

      match_debug_messages({
        'attach.attach(1): Attaching (trigger=BufNewFile)',
        np(revparse_pat),
        np('system.system: git .* config user.name'),
        np(
          'system.system: git .* ls%-files %-%-stage %-%-others %-%-exclude%-standard %-%-eol '
            .. path_pattern(newfile)
        ),
        'attach.attach(1): Cannot resolve file in repo',
      })

      check({ status = { head = 'main' } })
    end)

    it("doesn't attach to non-existent files with non-existent sub-dirs", function()
      edit(scratch .. '/does/not/exist')

      match_debug_messages({
        'attach.attach(1): Attaching (trigger=BufNewFile)',
        n('attach.attach(1): Not a path'),
      })

      helpers.pcall_err(get_buf_var, 0, 'gitsigns_head')
      helpers.pcall_err(get_buf_var, 0, 'gitsigns_status_dict')
    end)

    it('can run copen', function()
      command('copen')
      match_debug_messages({
        'attach.attach(2): Attaching (trigger=BufReadPost)',
        n('attach.attach(2): Non-normal buffer'),
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
      config.current_line_blame_opts = { delay = 1 }
      setup_gitsigns(config)
    end)

    local function stub_notify_once()
      exec_lua(function()
        _G.__gitsigns_notify_once_orig = vim.notify_once
        vim.notify_once = function() end
      end)
    end

    local function restore_notify_once()
      exec_lua(function()
        if _G.__gitsigns_notify_once_orig then
          vim.notify_once = _G.__gitsigns_notify_once_orig
          _G.__gitsigns_notify_once_orig = nil
        end
      end)
    end

    after_each(function()
      restore_notify_once()
    end)

    local function blame_line_ui_test(autocrlf, file_ending)
      setup_test_repo()
      exec_lua([[vim.g.editorconfig = false]])

      git('config', 'core.autocrlf', autocrlf)
      if file_ending == 'dos' then
        write_to_file(newfile, { 'This', 'is', 'a', 'windows', 'file' }, {
          newline = '\r\n',
        })
      else
        write_to_file(newfile, { 'This', 'is', 'a', 'windows', 'file' })
      end

      git('add', newfile)
      git('commit', '-m', 'commit on main')

      edit(newfile)
      feed('gg')
      check({ signs = {} })

      screen:expect({
        grid = [[
        ^{MATCH:This {6: You, .*}}|
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

    it('falls back when function formatters return invalid virt_text', function()
      -- nvim 0.10.4 can hang screen tests that render notify_once messages.
      -- This spec only cares about falling back to the default formatter.
      stub_notify_once()

      exec_lua(function()
        require('gitsigns.config').config.current_line_blame_formatter = function()
          return 'not virt_text'
        end
      end)

      setup_test_repo()
      edit(test_file)
      feed('gg')
      check({ signs = {} })

      expectf(function()
        local line = exec_lua('return vim.b.gitsigns_blame_line')
        return line ~= nil and line ~= 'not virt_text' and line:match('^ You, ') ~= nil
      end)
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
      config.current_line_blame_opts = {
        virt_text_pos = 'right_align',
        delay = 1,
      }
      setup_gitsigns(config)
    end)

    it('with nowrap', function()
      edit(test_file)
      command('set nowrap')
      feed('gg')

      screen:expect({
        grid = [[
        ^short {MATCH:{6: You, .*}}|
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
        ^short {MATCH:{6: You, .*}}|
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
        {MATCH:aaaaa {6: You, .*}}|
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

  describe('configuration', function()
    it('validates union-typed fields', function()
      helpers.setup_path()

      for _, case in ipairs({
        { field = 'current_line_blame_formatter', value = 1 },
        { field = 'current_line_blame_formatter_nc', value = 1 },
        { field = 'blame_formatter', value = true },
      }) do
        local result = exec_lua(function(field, value)
          local ok, err = pcall(require('gitsigns.config').build, {
            [field] = value,
          })
          return {
            ok = ok,
            err = tostring(err),
          }
        end, case.field, case.value)

        eq(false, result.ok)
        eq(true, result.err:find(case.field, 1, true) ~= nil)
      end
    end)
  end)

  describe('on_attach()', function()
    it('can prevent attaching to a buffer', function()
      setup_test_repo({ no_add = true })
      setup_gitsigns(config, true)

      edit(test_file)
      match_debug_messages({
        'attach.attach(1): Attaching (trigger=BufReadPost)',
        np(revparse_pat),
        np('system.system: git .* rev%-parse %-%-short HEAD'),
        np('system.system: git .* config user.name'),
        np(
          'system.system: git .* %-%-git%-dir .* %-%-stage %-%-others %-%-exclude%-standard %-%-eol.*'
        ),
        np('system.system: git .* check%-attr diff %-%-stdin'),
        n('attach.attach(1): User on_attach() returned false'),
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
        local messages = {
          'attach.attach(1): Attaching (trigger=BufNewFile)',
          np(revparse_pat),
          np('system.system: git .* config user.name'),
          np('system.system: git .* ls%-files .*'),
          n('attach.attach(1): Cannot resolve file in repo'),
        }

        if fn.has('win32') == 1 then
          table.insert(
            messages,
            5,
            p(vim.pesc('system.system: cygpath --absolute --unix ') .. path_pattern(newfile))
          )
        end

        match_debug_messages(messages)
        command('write')

        local messages = {
          'attach.attach(1): Attaching (trigger=BufWritePost)',
          np(revparse_pat),
          np('system.system: git .* ls%-files .*'),
        }

        if not internal_diff then
          table.insert(
            messages,
            np(vim.pesc('system.system: git ') .. '.* diff .* .*[\\/].* .*[\\/].*')
          )
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

      it('can manually attach untracked files with --force (#1026)', function()
        config.attach_to_untracked = false
        setup_gitsigns(config)

        edit(newfile)
        feed('iline<esc>')
        command('write')

        check({
          status = { head = 'main' },
          signs = {},
        })

        command('Gitsigns attach --force')

        check({
          status = { head = 'main', added = 1, changed = 0, removed = 0 },
          signs = { untracked = 1 },
        })

        command('Gitsigns stage_buffer')

        check({
          status = { head = 'main', added = 0, changed = 0, removed = 0 },
          signs = {},
        })
      end)

      it('tracks files in new repos', function()
        config.watch_gitdir.enable = true
        setup_gitsigns(config)
        helpers.touch(newfile)
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

        helpers.stage_hunk()

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

    -- Neovim may emit a varying number of path echoes before the stable quickfix message.
    expectf(function()
      screen:sleep(10)

      local messages = screen.messages
      local message = messages[#messages]
      local scratch_path0 = scratch:gsub('\\', '/')
      local scratch_path = vim.fs.normalize(scratch_path0)

      eq('quickfix', message.kind)
      eq('(1 of 2): hello ben', message.content[1][2])

      for i = 1, #messages - 1 do
        local entry = messages[i]
        local path0 = entry.content[1][2]:gsub('\\', '/')
        local path = vim.fs.normalize(path0)

        eq('', entry.kind)
        assert(
          vim.startswith(path, scratch_path .. '/'),
          ('unexpected path message: %s'):format(path)
        )
      end
    end, 10)

    match_debug_messages({
      'gitsigns.attach_autocmd(2): Attaching is disabled',
      n('gitsigns.attach_autocmd(3): Attaching is disabled'),
      n('gitsigns.attach_autocmd(4): Attaching is disabled'),
      n('gitsigns.attach_autocmd(5): Attaching is disabled'),
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

  it('redraws statuscolumn signs after async updates', function()
    setup_test_repo()
    setup_gitsigns(config)
    edit(test_file)
    exec_lua(function()
      vim.wo.signcolumn = 'yes'
      vim.wo.statuscolumn = "%{%v:lua.require'gitsigns'.statuscolumn()%}"
    end)

    wait_for_attach()
    feed('x')
    check({
      status = { head = 'main', added = 0, changed = 1, removed = 0 },
      signs = { changed = 1 },
    })

    screen:expect({ any = [[{2:~}{5: }^his]] })
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

    screen:expect({
      grid = [[
      ^Lorem ipsum         |
      {6:~                   }|
    ]],
    })

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
    screen:try_resize(30, 5)
    edit(test_file)
    wait_for_attach()

    -- Remove newline at end of file (`printf a >a`)
    local f = assert(io.open(test_file, 'wb'))
    f:write('a') -- Write without trailing newline
    f:close()

    command_wait_gitsigns_update('checktime')
    expectf(function()
      local hunk = exec_lua(function()
        return require('gitsigns').get_hunks()[1]
      end)
      return hunk and (hunk.added.no_nl_at_eof or hunk.removed.no_nl_at_eof)
    end)
    feed('mhp')
    screen:expect({ any = [[\ No newline at end of file]] })
  end)
end)

describe('gitsigns attach', function()
  local config --- @type table

  before_each(function()
    clear()
    refresh_paths()
    config = vim.deepcopy(test_config)
    helpers.chdir_tmp()
  end)

  after_each(function()
    cleanup()
  end)

  --- @param bufnr integer
  --- @param ctx Gitsigns.GitContext
  local function attach_with_context(bufnr, ctx)
    exec_lua(function(bufnr0, ctx0)
      local async = require('gitsigns.async')
      async
        .run(require('gitsigns.attach').attach, {
          bufnr = bufnr0,
          ctx = ctx0,
          trigger = 'test',
        })
        :wait(5000)
    end, bufnr, ctx)
    wait_for_attach(bufnr)
  end

  it('handle #888', function()
    setup_test_repo()

    local path1 = scratch .. '/cargo.toml'
    local subdir = scratch .. '/subdir'
    local path2 = subdir .. '/cargo.toml'

    write_to_file(path1, { 'some text' })
    git('add', path1)
    git('commit', '-m', 'add cargo')

    -- move file and stage move
    helpers.mkdir(subdir)
    helpers.move(path1, path2)
    git('add', path1, path2)

    config.base = 'HEAD'
    setup_gitsigns(config)
    edit(path1)
    wait_for_attach()
    command('write')
    expectf(function()
      return exec_lua(function()
        local bufnr = vim.api.nvim_get_current_buf()
        local cache = require('gitsigns.cache').cache[bufnr]
        return cache ~= nil and cache.git_obj.file == vim.api.nvim_buf_get_name(bufnr)
      end)
    end)
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
      'attach.attach(1): Empty git obj',
    })
  end)

  it('attaches to a tracked file in a subdirectory', function()
    helpers.git_init_scratch()

    local relpath = 'sub/test.txt'
    local file = scratch .. '/' .. relpath

    write_to_file(file, { 'hello', 'world' })
    git('add', file)
    git('commit', '-m', 'add nested file')

    setup_gitsigns(config)
    edit(file)
    wait_for_attach()

    local result = exec_lua(function(bufnr)
      local cache = assert(require('gitsigns.cache').cache[bufnr])
      return {
        relpath = cache.git_obj.relpath,
        object_name = cache.git_obj.object_name or '',
        toplevel = cache.git_obj.repo.toplevel,
      }
    end, api.nvim_get_current_buf())

    eq(relpath, result.relpath)
    eq(false, result.object_name == '')
    eq_path(scratch, result.toplevel)
  end)

  it('attaches with a relative file path in the git context', function()
    helpers.git_init_scratch()

    local relpath = 'sub/relative.txt'
    local file = scratch .. '/' .. relpath

    write_to_file(file, { 'hello', 'world' })
    git('add', file)
    git('commit', '-m', 'add relative file')

    config.auto_attach = false
    setup_gitsigns(config)
    edit(file)

    attach_with_context(api.nvim_get_current_buf(), {
      file = relpath,
      gitdir = scratch .. '/.git',
      toplevel = scratch,
    })

    local result = exec_lua(function(bufnr)
      local cache = assert(require('gitsigns.cache').cache[bufnr])
      return {
        relpath = cache.git_obj.relpath,
        object_name = cache.git_obj.object_name or '',
        file = cache.git_obj.file,
      }
    end, api.nvim_get_current_buf())

    eq(relpath, result.relpath)
    eq(false, result.object_name == '')
    eq_path(file, result.file)
  end)

  it('can run diffthis/show when cwd is a subdir of a git repo (#1277)', function()
    helpers.git_init_scratch()
    local file = scratch .. '/sub/test'
    write_to_file(file, { 'hello' })
    git('add', file)
    git('commit', '-m', 'commit 1')
    command('cd ' .. vim.fs.dirname(file))

    setup_gitsigns(config)

    edit('test')
    wait_for_attach()

    command('Gitsigns show')

    local show_bufnr --- @type integer?
    expectf(function()
      show_bufnr = exec_lua(function()
        local bufnr = vim.api.nvim_get_current_buf()
        if not vim.api.nvim_buf_get_name(bufnr):match('^gitsigns://') then
          return
        end
        return bufnr
      end)
      return show_bufnr ~= nil
    end)
    wait_for_attach(show_bufnr)

    local gfile, toplevel, gitdir, abbrev_head = exec_lua(function()
      local git_obj = assert(require('gitsigns.cache').cache[1]).git_obj
      return git_obj.file, git_obj.repo.toplevel, git_obj.repo.gitdir, git_obj.repo.abbrev_head
    end)

    eq(('gitsigns://%s//:0:sub/test'):format(gitdir), api.nvim_buf_get_name(0))

    eq_path(file, gfile)
    eq_path(scratch, toplevel)
    eq_path(scratch .. '/.git', gitdir)
    eq('main', abbrev_head)
  end)

  it('does not error after git system callbacks (#1425)', function()
    setup_test_repo()
    setup_gitsigns(config)

    edit(test_file)
    wait_for_attach()

    local ok = exec_lua(function()
      local async = require('gitsigns.async')
      local git_cmd = require('gitsigns.git.cmd')

      return async
        .run(function()
          -- `git_cmd()` ultimately uses `vim.system`, whose on_exit callback runs
          -- in fast event context. Ensure we yield to the scheduler after the
          -- command completes so Neovim API calls here don't raise E5560.
          git_cmd({ '--version' }, { text = true })

          local b = vim.api.nvim_create_buf(false, true)
          vim.bo[b].buftype = 'nofile'
          vim.api.nvim_buf_delete(b, { force = true })
          return true
        end)
        :wait()
    end)

    eq(true, ok)
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
      'attach.attach(1): Empty git obj',
    })
  end)
end)
