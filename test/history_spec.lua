local helpers = require('test.gs_helpers')

local check = helpers.check
local clear = helpers.clear
local command = helpers.api.nvim_command
local edit = helpers.edit
local eq = helpers.eq
local exec_lua = helpers.exec_lua
local expectf = helpers.expectf
local feed = helpers.feed
local git = helpers.git
local setup_gitsigns = helpers.setup_gitsigns
local setup_test_repo = helpers.setup_test_repo
local test_config = helpers.test_config
local wait_for_attach = helpers.wait_for_attach
local write_to_file = helpers.write_to_file
local scratch --- @type string
local test_file --- @type string

helpers.env()

local function open_history_panel()
  eq(
    'gitsigns-history',
    exec_lua(function()
      local async = require('gitsigns.async')
      async.run(require('gitsigns.actions.history').history):wait(5000)
      return vim.bo.filetype
    end)
  )
end

local function open_history_panel_command(cmd)
  local filetype = exec_lua(function(cmdline)
    vim.cmd(cmdline)

    local history_win --- @type integer?
    local ok = vim.wait(5000, function()
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local bufnr = vim.api.nvim_win_get_buf(win)
        if
          vim.bo[bufnr].filetype == 'gitsigns-history'
          and vim.wo[win].statusline:find('<CR> open', 1, true) ~= nil
        then
          history_win = win
          return true
        end
      end
    end)

    if not ok or not history_win then
      return nil
    end

    vim.api.nvim_set_current_win(history_win)
    return vim.bo.filetype
  end, cmd)

  eq('gitsigns-history', filetype)
end

local function open_history_panel_from_source()
  eq(
    'gitsigns-history',
    exec_lua(function()
      local history_win = vim.api.nvim_get_current_win()
      local source_win --- @type integer?

      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if win ~= history_win then
          source_win = win
          break
        end
      end

      assert(source_win)
      vim.api.nvim_set_current_win(source_win)

      local async = require('gitsigns.async')
      async.run(require('gitsigns.actions.history').history):wait(5000)
      return vim.bo.filetype
    end)
  )
end

local function get_history_browser_state()
  return exec_lua(function()
    local history_win = vim.api.nvim_get_current_win()
    local history_bufnr = vim.api.nvim_get_current_buf()
    local source_win --- @type integer?
    local source_bufnr --- @type integer?

    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if win ~= history_win then
        source_win = win
        source_bufnr = vim.api.nvim_win_get_buf(win)
        break
      end
    end

    local lines = vim.api.nvim_buf_get_lines(history_bufnr, 0, -1, false)
    local namespaces = vim.api.nvim_get_namespaces()
    local ns = assert(namespaces.gitsigns_history_win)
    local state_ns = assert(namespaces.gitsigns_history_state)
    local marks = vim.api.nvim_buf_get_extmarks(history_bufnr, ns, 0, -1, { details = true })
    local state_marks =
      vim.api.nvim_buf_get_extmarks(history_bufnr, state_ns, 0, -1, { details = true })
    local row_hls = {} --- @type table<integer, string[]>
    local detail_lines = {} --- @type string[]
    local detail_row --- @type integer?
    local cursor_row --- @type integer?
    local cursor_hl --- @type string?
    local source_row --- @type integer?
    local source_hl --- @type string?

    for _, mark in ipairs(marks) do
      local row = mark[2] + 1
      local details = assert(mark[4])
      if type(details.hl_group) == 'string' then
        row_hls[row] = row_hls[row] or {}
        row_hls[row][#row_hls[row] + 1] = details.hl_group
      end
    end

    table.sort(state_marks, function(a, b)
      return a[1] < b[1]
    end)

    for _, mark in ipairs(state_marks) do
      local details = assert(mark[4])
      local row = mark[2] + 1
      if details.virt_lines then
        detail_row = row
        for _, chunks in ipairs(details.virt_lines) do
          local parts = {} --- @type string[]
          for _, chunk in ipairs(chunks) do
            parts[#parts + 1] = chunk[1]
          end
          detail_lines[#detail_lines + 1] = table.concat(parts)
        end
      elseif details.hl_group == 'CursorLine' then
        cursor_row = row
        cursor_hl = details.hl_group
      elseif details.hl_group == 'Visual' then
        source_row = row
        source_hl = details.hl_group
      end
    end

    return {
      columns = vim.o.columns,
      cursor_hl = cursor_hl,
      cursor_row = cursor_row,
      detail_lines = detail_lines,
      detail_row = detail_row,
      history_height = vim.api.nvim_win_get_height(history_win),
      history_col = vim.fn.win_screenpos(history_win)[2],
      history_name = vim.api.nvim_buf_get_name(history_bufnr),
      history_statusline = vim.wo[history_win].statusline,
      history_top = vim.fn.win_screenpos(history_win)[1],
      history_width = vim.api.nvim_win_get_width(history_win),
      history_winbar = vim.wo[history_win].winbar,
      lines = lines,
      row_hls = row_hls,
      screen_lines = vim.o.lines,
      source_col = source_win and vim.fn.win_screenpos(source_win)[2] or nil,
      source_height = source_win and vim.api.nvim_win_get_height(source_win) or nil,
      source_hl = source_hl,
      source_lines = source_bufnr and vim.api.nvim_buf_get_lines(source_bufnr, 0, -1, false) or nil,
      source_name = source_bufnr and vim.api.nvim_buf_get_name(source_bufnr) or nil,
      source_row = source_row,
      source_top = source_win and vim.fn.win_screenpos(source_win)[1] or nil,
      source_width = source_win and vim.api.nvim_win_get_width(source_win) or nil,
      tab_count = #vim.api.nvim_list_tabpages(),
      visible_bot = vim.fn.line('w$'),
      visible_top = vim.fn.line('w0'),
      win_count = #vim.api.nvim_tabpage_list_wins(0),
    }
  end)
end

local function has_hl(row_hls, row, name)
  for _, hl in ipairs(row_hls[row] or {}) do
    if hl == name then
      return true
    end
  end
  return false
end

local function setup_two_commit_history()
  setup_gitsigns(test_config)
  setup_test_repo({
    test_file_text = { 'one', 'two' },
  })

  write_to_file(test_file, { 'one', 'TWO' })
  git('add', test_file)
  git('commit', '-m', 'second commit')

  edit(test_file)
  check({
    status = { head = 'main', added = 0, changed = 0, removed = 0 },
    signs = {},
  })
end

describe('history', function()
  before_each(function()
    clear()
    scratch = helpers.scratch
    test_file = helpers.test_file
    helpers.chdir_tmp()
    helpers.setup_path()
  end)

  it('renders the current buffer history in the current tab', function()
    setup_two_commit_history()
    open_history_panel()

    local result = get_history_browser_state()

    eq(1, result.tab_count)
    eq(2, result.win_count)
    assert(result.history_top > assert(result.source_top))
    assert(result.history_height < assert(result.source_height))
    assert(
      result.history_height <= math.max(4, math.floor(math.max(result.screen_lines - 2, 1) * 0.35))
    )
    eq('CursorLine', result.cursor_hl)
    eq(1, result.cursor_row)
    eq(test_file, result.source_name)
    eq(1, result.source_row)
    eq(nil, result.detail_row)
    assert(result.history_name:match('^gitsigns%-history://'))
    assert(result.history_winbar:find('History', 1, true))
    assert(result.history_winbar:find('dummy.txt', 1, true))
    assert(not result.history_winbar:find('tester', 1, true))
    eq(
      ' <CR> open  v split  t tab  gv/gt commit  i info  q quit  ? menu ',
      result.history_statusline
    )
    eq(nil, result.detail_lines[1])
    eq(2, #result.lines)
    assert(result.lines[1]:match('^%x%x%x%x%x%x%x%x  second commit$'))
    assert(result.lines[2]:match('^%x%x%x%x%x%x%x%x  init commit$'))
    eq(true, has_hl(result.row_hls, 1, 'Directory'))

    feed('i')

    local expanded = get_history_browser_state()
    eq(1, expanded.detail_row)
    assert(expanded.detail_lines[1]:match('^  %d%d%d%d%-%d%d%-%d%d  tester$'))
    assert(expanded.detail_lines[2]:find('HEAD', 1, true))
    assert(expanded.detail_lines[2]:find('main', 1, true))
    assert(expanded.detail_lines[3]:match('^  changes %+1 %-1$'))
    eq(nil, expanded.detail_lines[4])

    feed('i')

    local collapsed = get_history_browser_state()
    eq(nil, collapsed.detail_row)
    eq(nil, collapsed.detail_lines[1])

    feed('j')

    local moved = get_history_browser_state()
    eq('CursorLine', moved.cursor_hl)
    eq(2, moved.cursor_row)
    eq(1, moved.source_row)

    feed('<CR>')

    expectf(function()
      local opened = get_history_browser_state()
      return opened.tab_count == 2
        and opened.cursor_hl == 'CursorLine'
        and opened.cursor_row == 2
        and opened.source_row == 2
        and opened.source_name ~= nil
        and opened.source_name:match('^gitsigns://') ~= nil
    end)

    feed('<CR>')

    expectf(function()
      local reopened = get_history_browser_state()
      return reopened.cursor_hl == 'CursorLine'
        and reopened.cursor_row == 2
        and reopened.source_row == 2
        and reopened.source_name ~= nil
        and reopened.source_name:match('^gitsigns://') ~= nil
        and vim.deep_equal(reopened.source_lines, { 'one', 'two' })
    end)
  end)

  it('does not retarget history from an unrelated unattached window', function()
    setup_two_commit_history()

    eq(
      false,
      exec_lua(function()
        vim.cmd.new()
        local async = require('gitsigns.async')
        async.run(require('gitsigns.actions.history').history):wait(5000)

        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
          local bufnr = vim.api.nvim_win_get_buf(win)
          if vim.bo[bufnr].filetype == 'gitsigns-history' then
            return true
          end
        end

        return false
      end)
    )
  end)

  it('follows renames', function()
    helpers.git_init_scratch()
    setup_gitsigns(test_config)

    local old_path = scratch .. '/old.txt'
    local new_path = scratch .. '/new.txt'

    write_to_file(old_path, { 'one' })
    git('add', old_path)
    git('commit', '-m', 'add original file')

    git('mv', old_path, new_path)
    git('commit', '-m', 'rename file')

    edit(new_path)
    wait_for_attach()

    open_history_panel()

    local lines = exec_lua('return vim.api.nvim_buf_get_lines(0, 0, -1, false)')
    eq(2, #lines)
    assert(lines[1]:find('rename file', 1, true))
    assert(lines[2]:find('add original file', 1, true))

    feed('i')

    local rename_info = get_history_browser_state()
    eq(1, rename_info.detail_row)
    assert(rename_info.detail_lines[1]:match('^  %d%d%d%d%-%d%d%-%d%d  tester$'))
    assert(rename_info.detail_lines[2]:find('HEAD', 1, true))
    assert(rename_info.detail_lines[2]:find('main', 1, true))
    assert(rename_info.detail_lines[3]:match('^  changes %+0 %-0$'))
    eq('  renamed from old.txt', rename_info.detail_lines[4])

    feed('i')

    feed('j')
    feed('<CR>')

    expectf(function()
      local state = get_history_browser_state()
      return state.win_count == 2
        and state.source_name ~= nil
        and state.source_name:match('^gitsigns://') ~= nil
        and state.source_name:find('old.txt', 1, true) ~= nil
        and state.history_winbar:find('old.txt', 1, true) ~= nil
        and state.detail_row == nil
        and state.source_row == 2
        and vim.deep_equal(state.source_lines, { 'one' })
    end)

    open_history_panel_from_source()

    local reopened = get_history_browser_state()
    eq(2, reopened.tab_count)
    eq(2, reopened.win_count)
    eq(2, #reopened.lines)
    assert(reopened.lines[1]:find('rename file', 1, true))
    assert(reopened.lines[2]:find('add original file', 1, true))
    eq('CursorLine', reopened.cursor_hl)
    eq(2, reopened.cursor_row)
    eq(2, reopened.source_row)
    eq(nil, reopened.detail_row)
    eq(nil, reopened.detail_lines[1])
  end)

  it('keeps detail paths anchored to the history path across renames', function()
    helpers.git_init_scratch()
    setup_gitsigns(test_config)

    local old_path = scratch .. '/old.txt'
    local new_path = scratch .. '/new.txt'

    write_to_file(old_path, { 'one' })
    git('add', old_path)
    git('commit', '-m', 'add original file')

    git('mv', old_path, new_path)
    git('commit', '-m', 'rename file')

    write_to_file(new_path, { 'two' })
    git('add', new_path)
    git('commit', '-m', 'update renamed file')

    edit(new_path)
    wait_for_attach()

    open_history_panel()
    feed('j')
    feed('j')
    feed('<CR>')

    expectf(function()
      local state = get_history_browser_state()
      return state.source_name ~= nil
        and state.source_name:match('^gitsigns://') ~= nil
        and state.source_name:find('old.txt', 1, true) ~= nil
        and state.source_row == 3
    end)

    open_history_panel_from_source()
    feed('k')
    feed('k')
    feed('i')

    local reopened = get_history_browser_state()
    eq(1, reopened.cursor_row)
    eq(1, reopened.detail_row)
    assert(reopened.detail_lines[3]:match('^  changes %+1 %-1$'))
    eq(false, vim.tbl_contains(reopened.detail_lines, '  old path new.txt'))
    eq(false, vim.tbl_contains(reopened.detail_lines, '  renamed from old.txt'))
  end)

  it('opens a revision beside a lone history panel in the current tab', function()
    setup_two_commit_history()
    open_history_panel()

    exec_lua(function()
      local history_win = vim.api.nvim_get_current_win()
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if win ~= history_win then
          vim.api.nvim_win_close(win, true)
        end
      end
      vim.api.nvim_set_current_win(history_win)
    end)

    feed('j')
    feed('<CR>')

    expectf(function()
      local state = get_history_browser_state()
      return state.tab_count == 1
        and state.win_count == 2
        and state.cursor_row == 2
        and state.source_row == 2
        and state.source_name ~= nil
        and state.source_name:match('^gitsigns://') ~= nil
    end)
  end)

  it('reopens history for a revision buffer in the current tab', function()
    setup_two_commit_history()
    open_history_panel()

    feed('j')
    feed('t')

    expectf(function()
      return exec_lua(function()
        local has_source_panel = false
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(vim.api.nvim_list_tabpages()[1])) do
          local bufnr = vim.api.nvim_win_get_buf(win)
          if vim.bo[bufnr].filetype == 'gitsigns-history' then
            has_source_panel = true
          end
        end
        return #vim.api.nvim_list_tabpages() == 2
          and not has_source_panel
          and vim.bo.filetype == 'gitsigns-history'
      end)
    end)

    open_history_panel_command('Gitsigns history')

    local reopened = get_history_browser_state()
    eq(2, reopened.tab_count)
    eq(2, reopened.win_count)
    eq('CursorLine', reopened.cursor_hl)
    eq(2, reopened.cursor_row)
    eq(2, reopened.source_row)
    assert(reopened.source_name:match('^gitsigns://') ~= nil)

    feed('k')
    feed('<CR>')

    expectf(function()
      local state = get_history_browser_state()
      return state.cursor_row == 1
        and state.source_row == 1
        and vim.deep_equal(state.source_lines, { 'one', 'TWO' })
    end)

    feed('j')
    feed('<CR>')

    expectf(function()
      local state = get_history_browser_state()
      return state.cursor_row == 2
        and state.source_row == 2
        and vim.deep_equal(state.source_lines, { 'one', 'two' })
    end)
  end)

  it('shows a synthetic source row when the shown revision did not touch the file', function()
    setup_two_commit_history()
    local other_file = scratch .. '/other.txt'
    write_to_file(other_file, { 'other' })
    git('add', other_file)
    git('commit', '-m', 'third commit')

    command('Gitsigns show HEAD')
    wait_for_attach()

    open_history_panel_command('Gitsigns history')

    local result = get_history_browser_state()
    eq(1, result.tab_count)
    eq(2, result.win_count)
    eq('CursorLine', result.cursor_hl)
    eq(1, result.cursor_row)
    eq(1, result.source_row)
    assert(result.source_name:match('^gitsigns://') ~= nil)
    assert(result.lines[1]:match('^%x%x%x%x%x%x%x%x  %* third commit$'))
    eq(true, has_hl(result.row_hls, 1, 'Special'))
    assert(result.lines[2]:find('second commit', 1, true))
    assert(result.lines[3]:find('init commit', 1, true))

    feed('i')

    local expanded = get_history_browser_state()
    eq(1, expanded.detail_row)
    assert(expanded.detail_lines[1]:match('^  %d%d%d%d%-%d%d%-%d%d  tester$'))
    assert(expanded.detail_lines[2]:find('HEAD', 1, true))
    assert(expanded.detail_lines[2]:find('main', 1, true))
    eq('  status unchanged in this commit', expanded.detail_lines[3])
    assert(expanded.detail_lines[4]:match('^  last changed %x%x%x%x%x%x%x%x  second commit$'))
    eq(nil, expanded.detail_lines[5])
  end)

  it('renders associated PRs asynchronously for expanded info only', function()
    local config = vim.deepcopy(test_config)
    config.gh = true
    setup_gitsigns(config)
    setup_test_repo({
      test_file_text = { 'line 0' },
    })

    for i = 1, 2 do
      write_to_file(test_file, { ('line %d'):format(i) })
      git('add', test_file)
      git('commit', '-m', ('commit %d'):format(i))
    end

    local shas = exec_lua(function(repo, path)
      return vim.fn.systemlist({ 'git', '-C', repo, 'log', '--format=%H', '--', path })
    end, scratch, 'dummy.txt')

    edit(test_file)
    check({
      status = { head = 'main', added = 0, changed = 0, removed = 0 },
      signs = {},
    })

    exec_lua(function(sha_list)
      local async = require('gitsigns.async')
      local prs_by_sha = {} --- @type table<string, gitsigns.gh.PrInfo[]>
      vim.g.gitsigns_history_pr_batches = {}

      for i, sha in ipairs(sha_list) do
        prs_by_sha[sha] = {
          {
            number = tostring(i),
            url = ('https://example.test/pr/%d'):format(i),
          },
        }
      end

      package.loaded['gitsigns.gh'] = {
        associated_prs_many = function(shas)
          async.schedule()
          vim.g.gitsigns_history_pr_batches[#vim.g.gitsigns_history_pr_batches + 1] =
            vim.deepcopy(shas)

          local ret = {} --- @type table<string, gitsigns.gh.PrInfo[]|false>
          for _, sha in ipairs(shas) do
            ret[sha] = prs_by_sha[sha] or false
          end
          return ret
        end,
      }
    end, shas)

    open_history_panel()

    eq({}, exec_lua('return vim.g.gitsigns_history_pr_batches'))

    feed('i')

    expectf(function()
      local result = get_history_browser_state()
      return result.lines[1]:find('#1', 1, true) == nil
        and vim.tbl_contains(result.detail_lines, '  prs #1')
    end)

    expectf(function()
      return vim.deep_equal(exec_lua('return vim.g.gitsigns_history_pr_batches'), { { shas[1] } })
    end)

    feed('j')

    expectf(function()
      local result = get_history_browser_state()
      return result.cursor_row == 2
        and result.lines[1]:find('#1', 1, true) == nil
        and result.lines[2]:find('#2', 1, true) == nil
        and vim.tbl_contains(result.detail_lines, '  prs #2')
    end)

    expectf(function()
      return vim.deep_equal(exec_lua('return vim.g.gitsigns_history_pr_batches'), {
        { shas[1] },
        { shas[2] },
      })
    end)
  end)

  it('retries expanded-info PR lookups after an inconclusive fetch', function()
    local config = vim.deepcopy(test_config)
    config.gh = true
    setup_gitsigns(config)
    setup_test_repo({
      test_file_text = { 'line 0' },
    })

    write_to_file(test_file, { 'line 1' })
    git('add', test_file)
    git('commit', '-m', 'commit 1')

    local shas = exec_lua(function(repo, path)
      return vim.fn.systemlist({ 'git', '-C', repo, 'log', '--format=%H', '--', path })
    end, scratch, 'dummy.txt')

    edit(test_file)
    check({
      status = { head = 'main', added = 0, changed = 0, removed = 0 },
      signs = {},
    })

    exec_lua(function(sha)
      local async = require('gitsigns.async')
      local calls = 0
      vim.g.gitsigns_history_pr_batches = {}

      package.loaded['gitsigns.gh'] = {
        associated_prs_many = function(shas)
          async.schedule()
          calls = calls + 1
          vim.g.gitsigns_history_pr_batches[#vim.g.gitsigns_history_pr_batches + 1] =
            vim.deepcopy(shas)

          if calls == 1 then
            return {}
          end

          return {
            [sha] = {
              {
                number = '1',
                url = 'https://example.test/pr/1',
              },
            },
          }
        end,
      }
    end, shas[1])

    open_history_panel()
    feed('i')

    expectf(function()
      local result = get_history_browser_state()
      return not vim.tbl_contains(result.detail_lines, '  prs #1')
        and not vim.tbl_contains(result.detail_lines, '  prs loading...')
        and vim.deep_equal(exec_lua('return vim.g.gitsigns_history_pr_batches'), { { shas[1] } })
    end)

    feed('i')
    feed('i')

    expectf(function()
      local result = get_history_browser_state()
      return vim.tbl_contains(result.detail_lines, '  prs #1')
        and vim.deep_equal(exec_lua('return vim.g.gitsigns_history_pr_batches'), {
          { shas[1] },
          { shas[1] },
        })
    end)
  end)

  it('opens vertically with the :vert modifier', function()
    setup_two_commit_history()
    open_history_panel_command('vert Gitsigns history')

    local result = get_history_browser_state()

    eq(1, result.tab_count)
    eq(2, result.win_count)
    eq(assert(result.history_top), assert(result.source_top))
    assert(result.history_col < assert(result.source_col))
    assert(result.history_width < assert(result.source_width))
    assert(result.history_width <= math.max(32, math.floor(result.columns * 0.4)))
    eq('CursorLine', result.cursor_hl)
    eq(1, result.cursor_row)
    eq(1, result.source_row)
  end)

  it('opens the history action picker on ?', function()
    setup_gitsigns(test_config)
    setup_test_repo()

    edit(test_file)
    check({
      status = { head = 'main', added = 0, changed = 0, removed = 0 },
      signs = {},
    })

    open_history_panel()

    exec_lua(function()
      _G.gitsigns_test_select_orig = vim.ui.select
      vim.g.gitsigns_history_prompt = nil
      vim.g.gitsigns_history_items = nil
      vim.ui.select = function(items, opts, on_choice)
        vim.g.gitsigns_history_prompt = opts and opts.prompt or nil
        vim.g.gitsigns_history_items = vim.tbl_map(function(item)
          return item.desc
        end, items)
        on_choice(nil)
      end
    end)

    feed('?')

    local result = exec_lua(function()
      local prompt = vim.g.gitsigns_history_prompt
      local items = vim.g.gitsigns_history_items
      vim.ui.select = _G.gitsigns_test_select_orig
      _G.gitsigns_test_select_orig = nil
      return { prompt = prompt, items = items }
    end)

    assert(result.prompt:match('^Gitsigns history: %x%x%x%x%x%x%x%x$'))
    eq({
      'Open buffer revision',
      'Open buffer revision in a vertical split',
      'Open buffer revision in a new tab',
      'Show commit in a vertical split',
      'Show commit in a new tab',
      'Toggle expanded inline info',
      'Close history',
    }, result.items)
  end)

  it('opens the selected commit', function()
    setup_two_commit_history()
    open_history_panel()

    feed('j')
    feed('s')

    expectf(function()
      return exec_lua(function()
        if vim.bo.filetype ~= 'git' then
          return false
        end

        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        return lines[1]:match('^commit %x+$') ~= nil
          and table.concat(lines, '\n'):find('init commit', 1, true) ~= nil
      end)
    end)
  end)
end)
