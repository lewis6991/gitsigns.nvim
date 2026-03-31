local helpers = require('test.gs_helpers')

local setup_gitsigns = helpers.setup_gitsigns
local feed = helpers.feed
local edit = helpers.edit
local check = helpers.check
local exec_lua = helpers.exec_lua
local api = helpers.api
local test_config = helpers.test_config
local clear = helpers.clear
local setup_test_repo = helpers.setup_test_repo
local eq = helpers.eq
local expectf = helpers.expectf
local git = helpers.git
local write_to_file = helpers.write_to_file
local scratch --- @type string
local test_file --- @type string

helpers.env()

local function refresh_paths()
  scratch = helpers.scratch
  test_file = helpers.test_file
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

local delay = 1

--- @param cmd string
local function command(cmd)
  api.nvim_command(cmd)

  -- Flaky tests, add a large delay between commands.
  -- Flakiness is due to actions being async and problems occur when an action
  -- is run while another action or update is running.
  -- Must wait for actions and updates to finish.
  if delay > 0 then
    helpers.sleep(delay)
  end
end

local function retry(f)
  local orig_delay = delay
  local ok, err --- @type boolean, string?

  for _ = 1, 20 do
    --- @type boolean, string?
    ok, err = pcall(f)
    if ok then
      delay = orig_delay
      return
    end
    delay = math.ceil(delay * 1.6)
    print('failed, retrying with delay', delay)
  end

  delay = orig_delay
  if err then
    error(err)
  end
end

--- @param start integer
--- @param dend integer
--- @param lines string[]
local function set_lines(start, dend, lines)
  api.nvim_buf_set_lines(0, start, dend, false, lines)
end

--- @param range [integer, integer]?
local function stage_hunk(range)
  exec_lua(function(range0)
    local async = require('gitsigns.async')

    if range0 == vim.NIL then
      range0 = nil
    end

    async
      .run(function()
        local err = async.await(1, function(cb)
          require('gitsigns').stage_hunk(range0, nil, cb)
        end)
        assert(not err, err)
      end)
      :wait(1000)
  end, range == nil and vim.NIL or range)
end

local function reset_buffer_index()
  exec_lua(function()
    local async = require('gitsigns.async')
    async
      .run(function()
        local err = async.await(1, require('gitsigns').reset_buffer_index)
        assert(not err, err)
      end)
      :wait(1000)
  end)
end

describe('actions', function()
  local orig_it = it
  local function it(desc, f)
    orig_it(desc, function()
      retry(f)
    end)
  end

  before_each(function()
    clear()
    refresh_paths()
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

    command('Gitsigns stage_hunk')
    check({
      status = { head = 'main', added = 0, changed = 0, removed = 0 },
      signs = {},
    })

    command('Gitsigns undo_stage_hunk')
    check({
      status = { head = 'main', added = 0, changed = 1, removed = 0 },
      signs = { changed = 1 },
    })

    command('Gitsigns stage_hunk')
    check({
      status = { head = 'main', added = 0, changed = 0, removed = 0 },
      signs = {},
    })

    command('Gitsigns stage_hunk')
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

    command('Gitsigns stage_buffer')
    check({
      status = { head = 'main', added = 0, changed = 0, removed = 0 },
      signs = {},
    })

    command('Gitsigns reset_buffer_index')
    check({
      status = { head = 'main', added = 0, changed = 2, removed = 0 },
      signs = { changed = 2 },
    })

    command('Gitsigns reset_hunk')
    check({
      status = { head = 'main', added = 0, changed = 1, removed = 0 },
      signs = { changed = 1 },
    })
  end)

  it('show_commit does not include ansi color codes', function()
    setup_test_repo()
    edit(test_file)
    check({
      status = { head = 'main', added = 0, changed = 0, removed = 0 },
      signs = {},
    })

    local lines = exec_lua(function()
      local async = require('gitsigns.async')
      local commit_buf = async
        .run(function()
          return require('gitsigns.actions.show_commit')('main', 'edit')
        end)
        :wait(1000)

      return vim.api.nvim_buf_get_lines(commit_buf, 0, -1, false)
    end)

    for _, line in ipairs(lines) do
      assert(not line:find('\27', 1, true), ('unexpected ANSI escape in line: %q'):format(line))
    end
  end)

  it('completes attach command arguments', function()
    local complete = function(arglead, line)
      return exec_lua(function(arglead0, line0)
        return require('gitsigns.cli').complete(arglead0, line0)
      end, arglead, line)
    end

    eq({}, complete('', 'Gitsigns attach '))
    eq({ '--force' }, complete('--f', 'Gitsigns attach --f'))
    eq({}, complete('tr', 'Gitsigns attach tr'))
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

    command('Gitsigns stage_hunk')
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
    command('Gitsigns stage_hunk')

    command('Gitsigns undo_stage_hunk')
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
        command('write')
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
    command('Gitsigns stage_hunk')
    check({ status = { head = 'main', added = 0, changed = 0, removed = 0 } })
  end)

  it('stages tracked changes after attach in a nested path', function()
    helpers.git_init_scratch()

    local relpath = 'sub/stage.txt'
    local file = scratch .. '/' .. relpath

    write_to_file(file, { 'hello', 'world' })
    git('add', file)
    git('commit', '-m', 'add nested file')

    edit(file)

    expectf(function()
      return exec_lua(function()
        return vim.b.gitsigns_status_dict.gitdir ~= nil
      end)
    end)

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
