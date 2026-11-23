local helpers = require('test.gs_helpers')

local api = helpers.api
local check = helpers.check
local clear = helpers.clear
local command = api.nvim_command
local command_wait_gitsigns_update = helpers.command_wait_gitsigns_update
local edit = helpers.edit
local eq = helpers.eq
local exec_lua = helpers.exec_lua
local feed = helpers.feed
local expectf = helpers.expectf
local git = helpers.git
local reset_buffer_index = helpers.reset_buffer_index
local setup_gitsigns = helpers.setup_gitsigns
local setup_test_repo = helpers.setup_test_repo
local stage_hunk = helpers.stage_hunk
local test_config = helpers.test_config
local wait_for_attach = helpers.wait_for_attach
local write_to_file = helpers.write_to_file
local scratch --- @type string
local test_file --- @type string

helpers.env()

--- Read the index without converting its line endings.
--- @return string
local function index_text()
  return exec_lua(function(dir)
    local result = vim.system({ 'git', '-C', dir, 'show', ':newfile.txt' }, { text = false }):wait()
    assert(result.code == 0, result.stderr)
    return result.stdout
  end, scratch)
end

--- @param exp_hunks string[]
local function expect_hunks(exp_hunks)
  expectf(function()
    --- @type table[]
    local hunks = exec_lua("return require('gitsigns').get_hunks()")
    if #exp_hunks ~= #hunks then
      local msg = {} --- @type string[]
      msg[#msg + 1] = ''
      msg[#msg + 1] = string.format(
        'Number of hunks do not match. Expected: %d, passed in: %d',
        #exp_hunks,
        #hunks
      )

      msg[#msg + 1] = '\nExpected hunks:'
      for _, h in ipairs(exp_hunks) do
        msg[#msg + 1] = h
      end

      msg[#msg + 1] = '\nPassed in hunks:'
      for _, h in ipairs(hunks) do
        msg[#msg + 1] = h.head
      end

      error(table.concat(msg, '\n'))
    end

    for i, hunk in ipairs(hunks) do
      eq(exp_hunks[i], hunk.head)
    end
  end)
end

--- Complete arguments through the user command's completion handler.
--- @param arglead string
--- @param line string
--- @return string[]
local function complete(arglead, line)
  return exec_lua(function(arglead0, line0)
    return require('gitsigns.cli').complete(arglead0, line0)
  end, arglead, line)
end

--- @param start integer
--- @param dend integer
--- @param lines string[]
local function set_lines(start, dend, lines)
  api.nvim_buf_set_lines(0, start, dend, false, lines)
end

describe('actions', function()
  before_each(function()
    clear()
    scratch = helpers.scratch
    test_file = helpers.test_file
    helpers.chdir_tmp()
    setup_gitsigns(test_config)
  end)

  it('works with commands', function()
    setup_test_repo()
    edit(test_file)

    feed('jjjccEDIT<esc>')
    check({
      status = { head = 'main', added = 0, changed = 1, removed = 0 },
      signs = { changed = 1 },
    })

    command_wait_gitsigns_update('Gitsigns stage_hunk')
    check({
      status = { head = 'main', added = 0, changed = 0, removed = 0 },
      signs = {},
    })

    command_wait_gitsigns_update('Gitsigns undo_stage_hunk')
    check({
      status = { head = 'main', added = 0, changed = 1, removed = 0 },
      signs = { changed = 1 },
    })

    command_wait_gitsigns_update('Gitsigns stage_hunk')
    check({
      status = { head = 'main', added = 0, changed = 0, removed = 0 },
      signs = {},
    })

    command_wait_gitsigns_update('Gitsigns stage_hunk')
    check({
      status = { head = 'main', added = 0, changed = 1, removed = 0 },
      signs = { changed = 1 },
    })

    -- Add multiple edits
    feed('ggccThat<esc>')

    check({
      status = { head = 'main', added = 0, changed = 2, removed = 0 },
      signs = { changed = 2 },
    })

    command_wait_gitsigns_update('Gitsigns stage_buffer')
    check({
      status = { head = 'main', added = 0, changed = 0, removed = 0 },
      signs = {},
    })

    command_wait_gitsigns_update('Gitsigns reset_buffer_index')
    check({
      status = { head = 'main', added = 0, changed = 2, removed = 0 },
      signs = { changed = 2 },
    })

    command_wait_gitsigns_update('Gitsigns reset_hunk')
    check({
      status = { head = 'main', added = 0, changed = 1, removed = 0 },
      signs = { changed = 1 },
    })
  end)

  for _, cancel in ipairs({ false, true }) do
    it(
      'ignores repeated picker callbacks after ' .. (cancel and 'cancellation' or 'selection'),
      function()
        local signs_enabled = exec_lua(function(cancel0)
          local async = require('gitsigns.async')
          local config = require('gitsigns.config').config
          local choose --- @type fun(item?: string)

          config.signcolumn = true
          vim.ui.select = function(_, _, callback)
            choose = callback
            return {
              close = function()
                error('picker handles must not be closed by async')
              end,
            }
          end

          local task = async.run(require('gitsigns.cli').run, { args = '', fargs = {} })
          choose(not cancel0 and 'toggle_signs' or nil)
          task:wait(1000)

          choose('toggle_signs')
          choose(nil)
          task:wait(1000)

          return config.signcolumn
        end, cancel)
        eq(cancel, signs_enabled)
      end
    )
  end

  it('shows a commit in the current window without ansi color codes', function()
    setup_test_repo()
    edit(test_file)
    check({
      status = { head = 'main', added = 0, changed = 0, removed = 0 },
      signs = {},
    })

    local source = api.nvim_get_current_buf()
    api.nvim_buf_set_lines(source, 0, -1, false, { 'unsaved' })
    local lines = exec_lua(function()
      local done = false
      require('gitsigns').show('main', nil, function(err)
        assert(not err, err)
        done = true
      end)
      assert(vim.wait(1000, function()
        return done
      end))

      return vim.api.nvim_buf_get_lines(0, 0, -1, false)
    end)

    eq(1, #api.nvim_tabpage_list_wins(0))
    eq('git', exec_lua('return vim.bo.filetype'))
    eq(false, exec_lua('return vim.bo.modifiable'))
    eq({ 'unsaved' }, api.nvim_buf_get_lines(source, 0, -1, false))
    for _, line in ipairs(lines) do
      assert(not line:find('\27', 1, true), ('unexpected ANSI escape in line: %q'):format(line))
    end
  end)

  it('completes action command arguments', function()
    eq(true, vim.tbl_contains(complete('', 'vertical Gits '), 'attach'))
    eq({ '--bufnr=', '--force', '--trigger=' }, complete('', 'Gitsigns attach '))
    eq({ '--ignore_whitespace' }, complete('', 'Gitsigns blame '))
    eq({ '--full', '--ignore_whitespace' }, complete('', 'Gitsigns blame_line '))
    eq({ '--force' }, complete('--f', 'Gitsigns attach --f'))
    eq({ '--force=true', '--force=false' }, complete('--force=', 'Gitsigns attach --force='))
    eq({ '--trigger=' }, complete('--t', 'Gitsigns attach --t'))
    eq({ '--force' }, complete('--f', 'vertical Gitsigns attach --f'))
    eq({ '--force' }, complete('--f', 'vertical Gits attach --f'))

    eq({ 'true', 'false', '--global' }, complete('', 'Gitsigns change_base main '))
    eq(
      { '--global=true', '--global=false' },
      complete('--global=', 'Gitsigns change_base main --global=')
    )
    eq({ '--split=', '--unified', '--vertical' }, complete('--', 'Gitsigns diffthis --'))
    eq(
      { '--vertical=true', '--vertical=false' },
      complete('--vertical=', 'Gitsigns diffthis --vertical=')
    )
    eq({
      '--split=aboveleft',
      '--split=belowright',
      '--split=topleft',
      '--split=botright',
    }, complete('--split=', 'Gitsigns diffthis --split='))
    eq({ '--open=' }, complete('', 'Gitsigns show main '))
    eq(
      { '--open=edit', '--open=split', '--open=vsplit', '--open=tabnew' },
      complete('--open=', 'Gitsigns show main --open=')
    )
    eq({ 'next' }, complete('n', 'Gitsigns nav_hunk n'))
    eq(
      { '--target=unstaged', '--target=staged', '--target=all' },
      complete('--target=', 'Gitsigns next_hunk --target=')
    )
    eq({ '--full' }, complete('--f', 'Gitsigns blame_line --f'))
    eq({ '--full=true', '--full=false' }, complete('--full=', 'Gitsigns blame_line --full='))
    eq({ '--open' }, complete('--o', 'Gitsigns setqflist attached --o'))
    eq(
      { '--open=true', '--open=false' },
      complete('--open=', 'Gitsigns setqflist attached --open=')
    )
    eq({}, complete('', 'Gitsigns stage_hunk '))
    eq({}, complete('--g', 'Gitsigns reset_hunk --g'))
    eq({ 'attached', 'all' }, complete('', 'Gitsigns setloclist 0 '))
    eq({ 'true', 'false', 'nil' }, complete('', 'Gitsigns toggle_signs '))
  end)

  it('completes diff revisions and paths', function()
    setup_test_repo()
    api.nvim_set_current_dir(scratch)
    write_to_file(scratch .. '/src/new file%.lua', { 'new' })
    write_to_file(scratch .. '/--flag', { 'flag' })
    eq({ 'main' }, complete('ma', 'Gitsigns diff ma'))
    eq({ '--', '--commit', '--diff=', '--unified' }, complete('--', 'Gitsigns diff --'))
    eq({ 'main' }, complete('ma', 'Gitsigns diff --commit ma'))
    eq({ '--', '--diff=', '--unified' }, complete('--', 'Gitsigns diff --commit --'))
    eq({ '--diff=' }, complete('--d', 'Gitsigns diff --d'))
    eq(
      { '--diff=none', '--diff=split', '--diff=unified' },
      complete('--diff=', 'Gitsigns diff --diff=')
    )
    eq({ '--diff=none' }, complete('--diff=n', 'Gitsigns diff --diff=n'))
    eq({ 'main' }, complete('ma', 'Gitsigns diff --diff=none ma'))
    eq({ '--', '--commit' }, complete('--', 'Gitsigns diff --diff=none --'))
    eq({ 'main' }, complete('ma', 'Gitsigns diff --diff=unified ma'))
    eq({ 'main' }, complete('ma', 'Gitsigns diff --unified ma'))
    eq(
      { '--flag', '--', '--commit', '--diff=', '--unified' },
      complete('--', 'Gitsigns diff HEAD --')
    )
    eq({ '--unified' }, complete('--u', 'Gitsigns diff HEAD~ --u'))
    eq(
      { '--diff=none', '--diff=split', '--diff=unified' },
      complete('--diff=', 'Gitsigns diff HEAD~ --diff=')
    )
    eq({ '--flag', '--', '--commit' }, complete('--', 'Gitsigns diff HEAD~ --unified --'))
    eq({}, complete('--u', 'Gitsigns diff HEAD~ -- --u'))
    eq({ '--flag' }, complete('--f', 'Gitsigns diff -- --f'))
    local backslash = exec_lua("return vim.fn.has('win32') == 1 and not vim.o.shellslash")
    local matches = { 'src' .. (backslash and '\\\\' or '/') .. 'new\\ file%.lua' }
    for _, prefix in ipairs({
      '-- ',
      'HEAD ',
      'HEAD -- --flag ',
      'HEAD --flag ',
      '--diff=none -- ',
      '--diff=none HEAD ',
      '--diff=unified -- ',
      '--diff=unified HEAD ',
      '--unified -- ',
      '--unified HEAD ',
      'HEAD~ --diff=none ',
      'HEAD~ --diff=unified -- ',
      'HEAD~ --unified ',
    }) do
      eq(matches, complete('src/n', 'Gitsigns diff ' .. prefix .. 'src/n'))
    end
    eq(matches, complete('src/new\\ f', 'Gitsigns diff -- src/new\\ f'))
    local args = api.nvim_parse_cmd('Gitsigns ' .. matches[1], {}).args
    eq(1, #args)
    helpers.eq_path('src/new file%.lua', args[1])
  end)

  it('parses named flag assignments', function()
    local result = exec_lua(function()
      local parse_args = require('gitsigns.cli.argparse').parse_args
      local _, named = parse_args('attach --force=true --trigger=git=hook --bufnr=5 key=va=lue')
      local _, extra =
        parse_args('blame --extra_opts=--ignore-revs-file=.git-blame-ignore-revs --extra_opts=-M')

      return {
        force = named.force,
        trigger = named.trigger,
        bufnr = named.bufnr,
        key = named.key,
        extra_opts = extra.extra_opts,
      }
    end)

    eq('true', result.force)
    eq('git=hook', result.trigger)
    eq('5', result.bufnr)
    eq('va=lue', result.key)
    eq({ '--ignore-revs-file=.git-blame-ignore-revs', '-M' }, result.extra_opts)
  end)

  it('runs actions with named flags', function()
    local result = exec_lua(function()
      local actions = require('gitsigns.actions')
      local cli = require('gitsigns.cli')

      local saved = {
        attach = actions.attach,
        blame = actions.blame,
        change_base = actions.change_base,
        diffthis = actions.diffthis,
        nav_hunk = actions.nav_hunk,
        setqflist = actions.setqflist,
      }

      local ret = {}

      actions.attach = function(opts)
        ret.attach = {
          bufnr = opts.bufnr,
          force = opts.force,
          trigger = opts.trigger,
        }
      end

      actions.blame = function(opts)
        ret.blame = {
          extra_opts = opts.extra_opts,
          ignore_whitespace = opts.ignore_whitespace,
        }
      end

      actions.change_base = function(base, global)
        ret.change_base = { base = base, global = global }
      end

      actions.diffthis = function(base, opts)
        ret.diffthis = {
          base = base,
          split = opts.split,
          vertical = opts.vertical,
        }
      end

      actions.nav_hunk = function(direction, opts)
        ret.nav_hunk = {
          count = opts.count,
          direction = direction,
          preview = opts.preview,
          target = opts.target,
        }
      end

      actions.setqflist = function(target, opts)
        ret.setqflist = {
          nr = opts.nr,
          open = opts.open,
          target = target,
        }
      end

      local ok, err = pcall(function()
        cli.run({ args = 'attach --bufnr=5 --force=true --trigger=command', range = 0, smods = {} })
        cli.run({
          args = 'blame --ignore_whitespace=true --extra_opts=-M --extra_opts=-C',
          range = 0,
          smods = {},
        })
        cli.run({ args = 'change_base HEAD~2 --global=true', range = 0, smods = {} })
        cli.run({
          args = 'diffthis HEAD~1 --vertical=true --split=aboveleft',
          range = 0,
          smods = {},
        })
        cli.run({ args = 'next_hunk --target=all --preview=false --count=2', range = 0, smods = {} })
        cli.run({ args = 'setqflist attached --open=false --nr=4', range = 0, smods = {} })
      end)

      actions.attach = saved.attach
      actions.blame = saved.blame
      actions.change_base = saved.change_base
      actions.diffthis = saved.diffthis
      actions.nav_hunk = saved.nav_hunk
      actions.setqflist = saved.setqflist

      if not ok then
        error(err)
      end

      return ret
    end)

    eq(5, result.attach.bufnr)
    eq(true, result.attach.force)
    eq('command', result.attach.trigger)

    eq(true, result.blame.ignore_whitespace)
    eq({ '-M', '-C' }, result.blame.extra_opts)

    eq('HEAD~2', result.change_base.base)
    eq(true, result.change_base.global)

    eq('HEAD~1', result.diffthis.base)
    eq(true, result.diffthis.vertical)
    eq('aboveleft', result.diffthis.split)

    eq(2, result.nav_hunk.count)
    eq('next', result.nav_hunk.direction)
    eq(false, result.nav_hunk.preview)
    eq('all', result.nav_hunk.target)

    eq('attached', result.setqflist.target)
    eq(false, result.setqflist.open)
    eq(4, result.setqflist.nr)
  end)

  it('does not emit duplicate GitSignsUpdate events for stage_hunk', function()
    setup_test_repo()
    edit(test_file)

    feed('jjjccEDIT<esc>')
    check({
      status = { head = 'main', added = 0, changed = 1, removed = 0 },
      signs = { changed = 1 },
    })

    exec_lua(function()
      _G.test_gitsigns_update_events = {}

      vim.api.nvim_create_autocmd('User', {
        group = vim.api.nvim_create_augroup('GitsignsUpdateTest', { clear = true }),
        pattern = 'GitSignsUpdate',
        callback = function(args)
          local bufnr = args.data and args.data.buffer
          if bufnr ~= vim.api.nvim_get_current_buf() then
            return
          end

          local status = vim.b[bufnr].gitsigns_status_dict
          _G.test_gitsigns_update_events[#_G.test_gitsigns_update_events + 1] = {
            added = status and status.added,
            changed = status and status.changed,
            removed = status and status.removed,
            head = status and status.head,
          }
        end,
      })
    end)

    command_wait_gitsigns_update('Gitsigns stage_hunk')
    check({
      status = { head = 'main', added = 0, changed = 0, removed = 0 },
      signs = {},
    })

    expectf(function()
      eq({
        {
          added = 0,
          changed = 0,
          removed = 0,
          head = 'main',
        },
      }, exec_lua('return _G.test_gitsigns_update_events'))
    end, 10)
  end)

  it('can undo staged add hunks', function()
    setup_test_repo()
    edit(test_file)

    set_lines(1, 1, { 'added-1', 'added-2' })
    expect_hunks({ '@@ -1 +2,2 @@' })

    api.nvim_win_set_cursor(0, { 2, 0 })
    command_wait_gitsigns_update('Gitsigns stage_hunk')

    command_wait_gitsigns_update('Gitsigns undo_stage_hunk')
    expect_hunks({ '@@ -1 +2,2 @@' })
  end)

  it('preserves foldenable in diffthis windows after staging a hunk', function()
    command('silent! %bwipe!')
    setup_test_repo()
    edit(test_file)

    feed('jjjccEDIT<esc>')
    check({
      status = { head = 'main', added = 0, changed = 1, removed = 0 },
      signs = { changed = 1 },
    })

    exec_lua(function()
      local async = require('gitsigns.async')
      async.run(require('gitsigns.actions.diffthis').diffthis, nil, {}):wait(1000)
    end)

    local rev_win --- @type integer?
    expectf(function()
      eq(2, #api.nvim_list_wins())
      local current = api.nvim_get_current_win()
      for _, win in ipairs(api.nvim_list_wins()) do
        if win ~= current then
          local buf = api.nvim_win_get_buf(win)
          if api.nvim_buf_get_name(buf):find('^gitsigns://') then
            rev_win = win
            break
          end
        end
      end
      eq(true, type(rev_win) == 'number' and rev_win > 0)
    end)
    assert(rev_win)

    api.nvim_set_option_value('foldenable', false, { scope = 'local', win = rev_win })

    stage_hunk()

    check({
      status = { head = 'main', added = 0, changed = 0, removed = 0 },
      signs = {},
    })

    expectf(function()
      eq(true, api.nvim_win_is_valid(rev_win))
      eq(false, api.nvim_get_option_value('foldenable', { scope = 'local', win = rev_win }))
    end)
  end)

  describe('staging partial hunks', function()
    before_each(function()
      setup_test_repo({ test_file_text = { 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H' } })
    end)

    before_each(function()
      helpers.git('reset', '--hard')
      edit(test_file)
      check({
        status = { head = 'main', added = 0, changed = 0, removed = 0 },
        signs = {},
      })
    end)
    describe('can stage add hunks', function()
      before_each(function()
        set_lines(2, 2, { 'c1', 'c2', 'c3', 'c4' })
        expect_hunks({ '@@ -2 +3,4 @@' })
      end)

      it('contained in range', function()
        stage_hunk({ 1, 7 })
        expect_hunks({})
      end)

      it('containing range', function()
        stage_hunk({ 4, 5 })
        expect_hunks({
          '@@ -2 +3,1 @@',
          '@@ -4 +6,1 @@',
        })
      end)

      it('from top range', function()
        stage_hunk({ 1, 4 })
        expect_hunks({ '@@ -4 +5,2 @@' })
      end)

      it('from bottom range', function()
        stage_hunk({ 4, 7 })
        expect_hunks({ '@@ -2 +3,1 @@' })

        reset_buffer_index()
        expect_hunks({ '@@ -2 +3,4 @@' })

        stage_hunk({ 4, 10 })
        expect_hunks({ '@@ -2 +3,1 @@' })
      end)
    end)

    describe('can stage modified-add hunks', function()
      before_each(function()
        set_lines(2, 4, { 'c1', 'c2', 'c3', 'c4', 'c5' })
        expect_hunks({ '@@ -3,2 +3,5 @@' })
      end)

      it('from top range containing mod', function()
        stage_hunk({ 2, 3 })
        expect_hunks({ '@@ -4,1 +4,4 @@' })
      end)

      it('from top range containing mod-add', function()
        stage_hunk({ 2, 5 })
        expect_hunks({ '@@ -5 +6,2 @@' })
      end)

      it('from bottom range containing add', function()
        stage_hunk({ 6, 8 })
        expect_hunks({ '@@ -3,2 +3,3 @@' })
      end)

      it('containing range containing add', function()
        command('write')
        stage_hunk({ 5, 6 })
        expect_hunks({
          '@@ -3,2 +3,2 @@',
          '@@ -6 +7,1 @@',
        })
      end)
    end)

    describe('can stage modified-remove hunks', function()
      before_each(function()
        set_lines(2, 7, { 'c1', 'c2', 'c3' })
        command_wait_gitsigns_update('write')
        expect_hunks({ '@@ -3,5 +3,3 @@' })
      end)

      it('from top range', function()
        expect_hunks({ '@@ -3,5 +3,3 @@' })

        stage_hunk({ 2, 3 })
        expect_hunks({ '@@ -4,4 +4,2 @@' })

        reset_buffer_index()
        expect_hunks({ '@@ -3,5 +3,3 @@' })

        stage_hunk({ 2, 4 })
        expect_hunks({ '@@ -5,3 +5,1 @@' })
      end)

      it('from bottom range', function()
        expect_hunks({ '@@ -3,5 +3,3 @@' })

        stage_hunk({ 4, 6 })
        expect_hunks({ '@@ -3,1 +3,1 @@' })

        reset_buffer_index()
        expect_hunks({ '@@ -3,5 +3,3 @@' })

        stage_hunk({ 5, 6 })
        expect_hunks({ '@@ -3,2 +3,2 @@' })
      end)
    end)

    it('can stage remove hunks', function()
      set_lines(2, 5, {})
      expect_hunks({ '@@ -3,3 +2 @@' })

      stage_hunk({ 2, 2 })
      expect_hunks({})
    end)

    it('can stage topdelete hunks', function()
      set_lines(0, 2, {})
      expect_hunks({ '@@ -1,2 +0 @@' })

      stage_hunk({ 1, 1 })
      expect_hunks({})
    end)
  end)

  local function check_cursor(pos)
    eq(pos, api.nvim_win_get_cursor(0))
  end

  it('can navigate hunks', function()
    setup_test_repo()
    edit(test_file)

    feed('dd')
    feed('4Gx')
    feed('6Gx')

    expect_hunks({
      '@@ -1,1 +0 @@',
      '@@ -5,1 +4,1 @@',
      '@@ -7,1 +6,1 @@',
    })

    check_cursor({ 6, 0 })
    command('Gitsigns next_hunk') -- Wrap
    check_cursor({ 1, 0 })
    command('Gitsigns next_hunk')
    check_cursor({ 4, 0 })
    command('Gitsigns next_hunk')
    check_cursor({ 6, 0 })

    command('Gitsigns prev_hunk')
    check_cursor({ 4, 0 })
    command('Gitsigns prev_hunk')
    check_cursor({ 1, 0 })
    command('Gitsigns prev_hunk') -- Wrap
    check_cursor({ 6, 0 })
  end)

  it('can navigate hunks (nowrap)', function()
    setup_test_repo()
    edit(test_file)

    feed('4Gx')
    feed('6Gx')
    feed('gg')

    expect_hunks({
      '@@ -4,1 +4,1 @@',
      '@@ -6,1 +6,1 @@',
    })

    command('set nowrapscan')

    check_cursor({ 1, 0 })
    command('Gitsigns next_hunk')
    check_cursor({ 4, 0 })
    command('Gitsigns next_hunk')
    check_cursor({ 6, 0 })
    command('Gitsigns next_hunk')
    check_cursor({ 6, 0 })

    feed('G')
    check_cursor({ 18, 0 })
    command('Gitsigns prev_hunk')
    check_cursor({ 6, 0 })
    command('Gitsigns prev_hunk')
    check_cursor({ 4, 0 })
    command('Gitsigns prev_hunk')
    check_cursor({ 4, 0 })
  end)

  it('can navigate EOF delete hunks', function()
    setup_test_repo()
    edit(test_file)

    check({
      status = { head = 'main', added = 0, changed = 0, removed = 0 },
      signs = {},
    })

    local line_count = exec_lua(function()
      local Hunks = require('gitsigns.hunks')
      local bufnr = vim.api.nvim_get_current_buf()
      local cache = assert(require('gitsigns.cache').cache[bufnr])
      local line_count0 = vim.api.nvim_buf_line_count(bufnr)

      cache.hunks = {
        Hunks.create_hunk(4, 1, 4, 1),
        Hunks.create_hunk(line_count0, 1, line_count0 + 1, 0),
      }

      return line_count0
    end)

    feed('gg')
    command('Gitsigns next_hunk')
    check_cursor({ 4, 0 })

    command('Gitsigns next_hunk')
    check_cursor({ line_count, 0 })

    eq(
      true,
      exec_lua(function()
        local bufnr = vim.api.nvim_get_current_buf()
        local bcache = assert(require('gitsigns.cache').cache[bufnr])
        local hunk, index = bcache:get_cursor_hunk()

        return hunk ~= nil
          and index == 2
          and hunk.type == 'delete'
          and hunk.added.start == vim.api.nvim_buf_line_count(bufnr) + 1
      end)
    )

    eq(
      'Hunk 2 of 2',
      exec_lua(function()
        require('gitsigns').preview_hunk()

        local popup = require('gitsigns.popup')
        local win = assert(popup.is_open('hunk'))
        local title =
          assert(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, 1, false)[1])

        popup.close('hunk')

        return title
      end)
    )

    command('Gitsigns next_hunk') -- Wrap
    check_cursor({ 4, 0 })

    command('set nowrapscan')
    api.nvim_win_set_cursor(0, { 4, 0 })

    command('Gitsigns next_hunk --count=2')
    check_cursor({ line_count, 0 })
  end)

  it('can stage hunks with no NL at EOF', function()
    setup_test_repo()
    local newfile = helpers.newfile
    exec_lua([[vim.g.editorconfig = false]])
    helpers.write_to_file(newfile, { 'This is a file with no nl at eof' }, {
      trailing_newline = false,
    })
    helpers.git('add', newfile)
    helpers.git('commit', '-m', 'commit on main')

    edit(newfile)
    check({ status = { head = 'main', added = 0, changed = 0, removed = 0 } })
    feed('x')
    check({ status = { head = 'main', added = 0, changed = 1, removed = 0 } })
    command_wait_gitsigns_update('Gitsigns stage_hunk')
    check({ status = { head = 'main', added = 0, changed = 0, removed = 0 } })
  end)

  describe('line endings', function()
    local file --- @type string

    local function show_index()
      command('Gitsigns show :%')
      expectf(function()
        eq('acwrite', exec_lua('return vim.bo.buftype'))
      end)
      wait_for_attach()
    end

    before_each(function()
      setup_test_repo()
      exec_lua([[vim.g.editorconfig = false]])
      file = helpers.newfile
      write_to_file(file, { 'one', 'two', 'three' })
      git('add', file)
      git('commit', '-m', 'Add file')
    end)

    for _, case in ipairs({
      { name = 'autocrlf', autocrlf = 'true' },
      { name = 'autocrlf input', autocrlf = 'input' },
      { name = 'a boolean autocrlf alias', autocrlf = 'ON' },
      { name = 'a numeric autocrlf value', autocrlf = '1k' },
      { name = 'a bare autocrlf key', bare = true },
      { name = 'a text attribute', attribute = '*.txt text eol=lf' },
    }) do
      it('compares and stages CRLF with ' .. case.name, function()
        if case.autocrlf then
          git('config', 'core.autocrlf', case.autocrlf)
        end
        if case.attribute then
          write_to_file(scratch .. '/.gitattributes', { case.attribute })
        end
        if case.bare then
          local config_file = assert(io.open(scratch .. '/.git/config', 'a'))
          config_file:write('\n[core]\n\tautocrlf\n')
          config_file:close()
        end

        edit(file)
        wait_for_attach()
        command('setlocal fileformat=dos | write')
        set_lines(1, 2, { 'TWO' })
        command('write')

        check({ status = { head = 'main', added = 0, changed = 1, removed = 0 } })
        api.nvim_win_set_cursor(0, { 2, 0 })

        command('Gitsigns reset_hunk')
        expectf(function()
          eq({ 'one', 'two', 'three' }, api.nvim_buf_get_lines(0, 0, -1, false))
        end)
        set_lines(1, 2, { 'TWO' })
        check({ status = { head = 'main', added = 0, changed = 1, removed = 0 } })
        stage_hunk()

        eq('one\nTWO\nthree\n', index_text())
        git('diff', '--quiet', '--', file)
      end)
    end

    for _, case in ipairs({
      { name = 'the text attribute is unset', attribute = true },
      { name = 'an empty autocrlf value overrides true' },
    }) do
      it('stages line-ending changes when ' .. case.name, function()
        if case.attribute then
          write_to_file(scratch .. '/.gitattributes', { '*.txt -text' })
        else
          git('config', 'core.autocrlf', 'true')
          git('config', '--add', 'core.autocrlf', '')
        end

        edit(file)
        wait_for_attach()
        command('setlocal fileformat=dos | write')
        check({ status = { head = 'main', added = 0, changed = 3, removed = 0 } })
        stage_hunk({ 1, 1 })

        eq('one\r\ntwo\nthree\n', index_text())
        check({ status = { head = 'main', added = 0, changed = 2, removed = 0 } })
        stage_hunk({ 2, 3 })

        eq('one\r\ntwo\r\nthree\r\n', index_text())
        git('diff', '--quiet', '--', file)
      end)
    end

    for _, case in ipairs({
      { name = 'a lone CR', line = 'tw\ro' },
      { name = 'a control byte', line = 'tw\1o' },
    }) do
      it('preserves line endings when Git detects binary content with ' .. case.name, function()
        git('config', 'core.autocrlf', 'true')
        edit(file)
        wait_for_attach()
        command('setlocal fileformat=dos')
        set_lines(1, 2, { case.line })
        command('write')

        check({ status = { head = 'main', added = 0, changed = 3, removed = 0 } })
        stage_hunk()

        eq('one\r\n' .. case.line .. '\r\nthree\r\n', index_text())
        git('diff', '--quiet', '--', file)
      end)
    end

    it('preserves index text when attributes change to text', function()
      git('config', 'core.autocrlf', 'false')
      write_to_file(file, { 'one', 'two', 'three' }, { newline = '\r\n' })
      git('add', file)
      local original = index_text()

      -- Changing attributes does not convert the blob already in the index.
      write_to_file(scratch .. '/.gitattributes', { '*.txt text' })
      write_to_file(file, { 'one', 'changed', 'three' }, { newline = '\r\n' })
      edit(file)
      wait_for_attach()

      command('Gitsigns reset_buffer')
      expectf(function()
        eq({ 'one\r', 'two\r', 'three\r' }, api.nvim_buf_get_lines(0, 0, -1, false))
      end)

      -- Git removes one CR before each newline. Keep the stored CR as content.
      command('write')
      eq({ 'one\r\r', 'two\r\r', 'three\r\r', '' }, helpers.fn.readfile(file, 'b'))
      git('diff', '--quiet', '--', file)

      show_index()
      eq({ 'one\r', 'two\r', 'three\r' }, api.nvim_buf_get_lines(0, 0, -1, false))

      -- Force the write and wait for it to finish, even though the text is unchanged.
      command('setlocal modified | write')
      expectf(function()
        eq(false, exec_lua('return vim.bo.modified'))
        eq(original, index_text())
      end)
    end)

    for _, case in ipairs({
      {
        name = 'some lines',
        lines = { 'one', 'keep\r', 'three' },
        written_lines = { 'one\r', 'keep\r\r', 'three\r', '' },
        index = 'one\nkeep\r\nthree\n',
      },
      {
        name = 'every line',
        lines = { 'one\r', 'keep\r', 'three\r' },
        written_lines = { 'one\r\r', 'keep\r\r', 'three\r\r', '' },
        index = 'one\r\nkeep\r\nthree\r\n',
      },
    }) do
      it('preserves literal CR on ' .. case.name .. ' of normalized text', function()
        write_to_file(scratch .. '/.gitattributes', { '*.txt text' })
        write_to_file(file, case.lines, { newline = '\r\n' })
        git('add', file)

        local changed = vim.deepcopy(case.lines)
        changed[2] = 'changed'
        write_to_file(file, changed, { newline = '\r\n' })
        edit(file)
        wait_for_attach()

        -- Public hunk lines must retain CR bytes that belong to the text.
        eq({ '-keep\r', '+changed' }, exec_lua('return require("gitsigns").get_hunks()[1].lines'))
        command('2Gitsigns reset_hunk')

        expectf(function()
          eq(case.lines, api.nvim_buf_get_lines(0, 0, -1, false))
        end)
        command('write')
        eq(case.written_lines, helpers.fn.readfile(file, 'b'))
        git('diff', '--quiet', '--', file)

        show_index()
        eq(case.lines, api.nvim_buf_get_lines(0, 0, -1, false))
        command('setlocal modified | write')
        expectf(function()
          eq(false, exec_lua('return vim.bo.modified'))
          eq(case.index, index_text())
        end)
      end)
    end

    for _, reset in ipairs({ 'reset_buffer', 'partial reset_hunk' }) do
      it('preserves literal CR across all hunks in ' .. reset, function()
        -- The existing index contains binary content; the edited file is plain text.
        write_to_file(scratch .. '/.gitattributes', { '*.txt -text' })
        write_to_file(file, { 'one', 'keep\r', 'three', 'four', 'fi\1ve', 'six' })
        git('add', file)
        write_to_file(scratch .. '/.gitattributes', { '*.txt text=auto' })
        write_to_file(
          file,
          { 'one', 'changed', 'three', 'four', 'changed-too', 'six' },
          { newline = '\r\n' }
        )
        edit(file)
        wait_for_attach()
        check({ status = { head = 'main', added = 0, changed = 2, removed = 0 } })

        if reset == 'reset_buffer' then
          command('Gitsigns reset_buffer')
        else
          -- Restoring the lower hunk makes the buffer count as binary before the next reset.
          command_wait_gitsigns_update('5Gitsigns reset_hunk')
          command('2Gitsigns reset_hunk')
        end

        expectf(function()
          eq(
            { 'one', 'keep\r', 'three', 'four', 'fi\1ve', 'six' },
            api.nvim_buf_get_lines(0, 0, -1, false)
          )
        end)
      end)
    end

    for _, reset in ipairs({ '1Gitsigns reset_hunk', 'Gitsigns reset_buffer' }) do
      it('resets mixed line endings in a DOS buffer with ' .. reset, function()
        git('config', 'core.autocrlf', 'false')
        write_to_file(file, { 'one\r', 'two', 'three' })
        git('add', file)
        write_to_file(file, { 'ONE', 'two', 'three' })
        edit(file)
        command('setlocal fileformat=dos')
        wait_for_attach()

        command(reset)
        expectf(function()
          eq({ 'one', 'two', 'three' }, api.nvim_buf_get_lines(0, 0, -1, false))
        end)
        command('write')
        eq({ 'one\r', 'two\r', 'three\r', '' }, helpers.fn.readfile(file, 'b'))
      end)
    end

    it('preserves CRLF index bytes when resetting and showing a Unix buffer', function()
      git('config', 'core.autocrlf', 'false')
      write_to_file(file, { 'one', 'two', 'three' }, { newline = '\r\n' })
      git('add', file)
      write_to_file(file, { 'one', 'changed', 'three' })
      edit(file)
      wait_for_attach()

      eq('unix', exec_lua('return vim.bo.fileformat'))
      eq('-two\r', exec_lua('return require("gitsigns").get_hunks()[1].lines[2]'))
      command('2Gitsigns reset_hunk')
      expectf(function()
        eq({ 'one', 'two\r', 'three' }, api.nvim_buf_get_lines(0, 0, -1, false))
      end)

      show_index()
      eq({ 'one\r', 'two\r', 'three\r' }, api.nvim_buf_get_lines(0, 0, -1, false))
    end)

    it('preserves a literal CR at EOF when resetting and showing DOS text', function()
      write_to_file(scratch .. '/.gitattributes', { '*.txt text=auto' })
      write_to_file(file, { 'one', 'keep\r' }, { newline = '\r\n', trailing_newline = false })
      git('add', file)
      write_to_file(file, { 'one', 'changed' }, { newline = '\r\n', trailing_newline = false })
      edit(file)
      wait_for_attach()

      -- Only the first line has a CRLF terminator; the final CR belongs to the text.
      eq(
        { '-one', '-keep\r', '+one', '+changed' },
        exec_lua('return require("gitsigns").get_hunks()[1].lines')
      )
      command('2Gitsigns reset_hunk')
      expectf(function()
        eq({ 'one', 'keep\r' }, api.nvim_buf_get_lines(0, 0, -1, false))
      end)

      show_index()
      eq({ 'one', 'keep\r' }, api.nvim_buf_get_lines(0, 0, -1, false))
    end)

    it('stages correctly after writing a CRLF index view', function()
      git('config', 'core.autocrlf', 'true')
      write_to_file(file, { 'one', 'two', 'three' }, { newline = '\r\n' })
      edit(file)
      wait_for_attach()
      local source = api.nvim_get_current_buf()

      show_index()
      -- Index buffers can use a different file format from the stored blob.
      command('setlocal fileformat=dos')
      set_lines(1, 2, { 'TWO' })
      command('write')
      expectf(function()
        eq(false, exec_lua('return vim.bo.modified'))
        eq('one\nTWO\nthree\n', index_text())
      end)

      api.nvim_set_current_buf(source)
      check({ status = { head = 'main', added = 0, changed = 1, removed = 0 } })
      api.nvim_win_set_cursor(0, { 2, 0 })
      stage_hunk()
      eq('one\ntwo\nthree\n', index_text())
      check({ status = { head = 'main', added = 0, changed = 0, removed = 0 } })
    end)

    it('normalizes CRLF when partially staging an untracked file', function()
      git('rm', '--cached', file)
      git('config', 'core.autocrlf', 'true')
      setup_gitsigns(vim.tbl_extend('force', test_config, { attach_to_untracked = true }))
      write_to_file(file, { 'one', 'two', 'three' }, { newline = '\r\n' })
      edit(file)
      wait_for_attach()

      stage_hunk({ 1, 1 })
      eq('one\n', index_text())
      check({ status = { head = 'main', added = 2, changed = 0, removed = 0 } })
      stage_hunk({ 2, 3 })
      eq('one\ntwo\nthree\n', index_text())
      check({ status = { head = 'main', added = 0, changed = 0, removed = 0 } })
    end)
  end)

  it('stages tracked changes after attach in a nested path', function()
    helpers.git_init_scratch()

    local relpath = 'sub/stage.txt'
    local file = scratch .. '/' .. relpath

    write_to_file(file, { 'hello', 'world' })
    git('add', file)
    git('commit', '-m', 'add nested file')

    edit(file)

    wait_for_attach()

    set_lines(0, 1, { 'changed' })

    expectf(function()
      local hunks = exec_lua(function(bufnr)
        local cache = assert(require('gitsigns.cache').cache[bufnr])
        return cache.hunks and #cache.hunks or 0
      end, api.nvim_get_current_buf())

      return hunks > 0
    end)

    stage_hunk()

    expectf(function()
      eq(
        relpath,
        vim.trim(helpers.fn.system({ 'git', '-C', scratch, 'diff', '--cached', '--name-only' }))
      )
    end)
  end)
end)
