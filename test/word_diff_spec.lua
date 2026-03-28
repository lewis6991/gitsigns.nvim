local helpers = require('test.gs_helpers')

local exec_lua = helpers.exec_lua
local eq = helpers.eq
local git = helpers.git
local setup_test_repo = helpers.setup_test_repo
local setup_gitsigns = helpers.setup_gitsigns
local test_config = helpers.test_config
local edit = helpers.edit
local clear = helpers.clear
local cleanup = helpers.cleanup
local expectf = helpers.expectf
local check = helpers.check
local test_file --- @type string

helpers.env()

local function refresh_paths()
  test_file = helpers.test_file
end

local function require_source_hls()
  if helpers.fn.has('nvim-0.12') == 0 then
    pending('requires Neovim 0.12+')
  end
end

local function require_window_scoped_deleted_preview()
  if helpers.fn.has('nvim-0.11') == 0 then
    pending('requires window-scoped deleted preview support')
  end
end

local function enable_lua_treesitter_on_filetype()
  exec_lua(function()
    vim.api.nvim_create_autocmd('FileType', {
      group = vim.api.nvim_create_augroup('gitsigns_word_diff_treesitter', { clear = true }),
      pattern = 'lua',
      callback = function(args)
        pcall(vim.treesitter.start, args.buf, 'lua')
        local ok, parser = pcall(vim.treesitter.get_parser, args.buf, 'lua')
        if ok and parser then
          pcall(parser.parse, parser, true)
        end
      end,
    })

    vim.cmd('syntax on')
    vim.bo.filetype = 'lua'
  end)
end

local function contains_hl(hl, group)
  if type(hl) == 'table' then
    return vim.tbl_contains(hl, group)
  end
  return hl == group
end

local function virt_hl_at_col(vline, col)
  local byte_col = 0
  for _, chunk in ipairs(vline) do
    local text, hl = chunk[1], chunk[2]
    if contains_hl(hl, 'GitSignsDeleteVirtLn') then
      local next_col = byte_col + #text
      if col < next_col then
        return hl
      end
      byte_col = next_col
    end
  end
end

local function deleted_preview_has_hl(group, bufnr)
  return exec_lua(function(target, source_bufnr)
    source_bufnr = source_bufnr or 0
    for _, ns in pairs(vim.api.nvim_get_namespaces()) do
      for _, mark in
        ipairs(vim.api.nvim_buf_get_extmarks(source_bufnr, ns, 0, -1, { details = true }))
      do
        local details = mark[4]
        if details and details.virt_lines and details.virt_lines_leftcol then
          for _, vline in ipairs(details.virt_lines) do
            for _, chunk in ipairs(vline) do
              local hl = chunk[2]
              if type(hl) == 'table' then
                if vim.tbl_contains(hl, target) then
                  return true
                end
              elseif hl == target then
                return true
              end
            end
          end
        end
      end
    end
    return false
  end, group, bufnr)
end

local function count_deleted_preview_marks(bufnr)
  return exec_lua(function(source_bufnr)
    source_bufnr = source_bufnr or 0
    local count = 0
    for _, ns in pairs(vim.api.nvim_get_namespaces()) do
      for _, mark in
        ipairs(vim.api.nvim_buf_get_extmarks(source_bufnr, ns, 0, -1, { details = true }))
      do
        local details = mark[4]
        if details and details.virt_lines and details.virt_lines_leftcol then
          count = count + 1
        end
      end
    end
    return count
  end, bufnr)
end

--- @param rows string[]
--- @param text string
--- @return boolean
describe('word diff', function()
  before_each(function()
    clear()
    refresh_paths()
    setup_gitsigns(vim.deepcopy(test_config))
  end)

  it('treats whitespace padding as a single region', function()
    local rems, adds = exec_lua(function()
      local diff = require('gitsigns.diff_int')
      local removed = { 'foo = 1', 'bar = 2' }
      local added = { 'foo     = 1', 'bar     = 2' }
      return diff.run_word_diff(removed, added)
    end)
    eq({
      { 1, 'add', 5, 5 },
      { 2, 'add', 5, 5 },
    }, rems)
    eq({
      { 1, 'add', 5, 9 },
      { 2, 'add', 5, 9 },
    }, adds)
  end)

  it('anchors indentation changes to the start of the line', function()
    local rems, adds = exec_lua(function()
      local diff = require('gitsigns.diff_int')
      local removed = { '  foo = 1' }
      local added = { '        foo = 1' }
      return diff.run_word_diff(removed, added)
    end)
    eq({ { 1, 'add', 3, 3 } }, rems)
    eq({ { 1, 'add', 3, 9 } }, adds)
  end)

  it('highlights only changed characters inside a word', function()
    local rems, adds = exec_lua(function()
      local diff = require('gitsigns.diff_int')
      local removed = { 'local foo = 1' }
      local added = { 'local foz = 1' }
      return diff.run_word_diff(removed, added)
    end)
    eq({ { 1, 'change', 9, 10 } }, rems)
    eq({ { 1, 'change', 9, 10 } }, adds)
  end)
end)

describe('inline preview', function()
  before_each(function()
    clear()
    refresh_paths()
  end)

  after_each(function()
    cleanup()
  end)

  it('word diff aligns highlights after multibyte characters', function()
    if helpers.fn.has('nvim-0.11') == 0 then
      pending('requires Neovim 0.11+')
    end
    setup_test_repo({ test_file_text = { 'unchanged', 'éx' } })
    local config = vim.deepcopy(test_config)
    config.word_diff = true
    setup_gitsigns(config)
    edit(test_file)

    exec_lua(function()
      vim.api.nvim_buf_set_lines(0, 1, 2, false, { 'éy' })
      vim.api.nvim_win_set_cursor(0, { 2, 0 })
    end)

    exec_lua(function()
      require('gitsigns').refresh()
    end)

    expectf(function()
      local hunks = exec_lua("return require('gitsigns').get_hunks()")
      eq(1, #hunks)
    end)

    local expected_start, expected_end = exec_lua(function()
      local line = assert(vim.api.nvim_buf_get_lines(0, 1, 2, false)[1])
      -- Use UTF-32 indexes so we can count characters.
      return vim.str_byteindex(line, 'utf-32', 1), vim.str_byteindex(line, 'utf-32', 2)
    end)

    local start_col, end_col = exec_lua(function()
      require('gitsigns.async').run(require('gitsigns.actions.preview').preview_hunk_inline):wait()

      local start_col0, end_col0 --- @type integer?, integer?
      vim.wait(1000, function()
        local ns = vim.api.nvim_get_namespaces().gitsigns_preview_inline
        local marks = vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })
        for _, mark in ipairs(marks) do
          local details = mark[4]
          if details and details.hl_group == 'GitSignsChangeInline' then
            start_col0 = mark[3]
            end_col0 = details.end_col
            return true
          end
        end
      end)
      return start_col0, end_col0
    end)

    eq(expected_start, start_col)
    eq(expected_end, end_col)
  end)

  it('deleted highlights each removed line exactly once', function()
    setup_test_repo({
      test_file_text = {
        'alpha',
        'bravo',
        'charlie',
      },
    })
    setup_gitsigns(test_config)
    edit(test_file)

    helpers.api.nvim_buf_set_lines(0, 0, 2, false, {})

    expectf(function()
      local hunk = exec_lua(function()
        return require('gitsigns').get_hunks()[1]
      end)
      assert(hunk and hunk.removed.count == 2)
    end)

    local wins_before, wins_after, virt_line_count, leftcol = exec_lua(function()
      local wins0 = #vim.api.nvim_list_wins()
      local markid = require('gitsigns.async')
        .run(require('gitsigns.actions.preview').preview_hunk_inline)
        :wait()
      assert(markid, 'preview mark not found')
      local ns = vim.api.nvim_get_namespaces().gitsigns_preview_inline
      local marks = vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })
      local details --- @type vim.api.keyset.get_extmark_item[4]?
      for _, mark in ipairs(marks) do
        if mark[1] == markid then
          details = mark[4]
          break
        end
      end
      assert(details and details.virt_lines, 'preview virtual lines not found')
      return wins0, #vim.api.nvim_list_wins(), #details.virt_lines, details.virt_lines_leftcol
    end)

    eq(wins_before, wins_after)
    eq(2, virt_line_count)
    eq(true, leftcol)
  end)

  it('shows top-of-file deletions with virtual lines', function()
    setup_test_repo({
      test_file_text = {
        'alpha',
        'bravo',
      },
    })
    setup_gitsigns(test_config)
    edit(test_file)

    exec_lua(function()
      vim.api.nvim_buf_set_lines(0, 0, 1, false, {})
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
    end)

    expectf(function()
      local hunk = exec_lua(function()
        return require('gitsigns').get_hunks()[1]
      end)
      assert(hunk and hunk.type == 'delete' and hunk.added.start == 0)
    end)

    local wins_before, wins_after, virt_line_count, leftcol, top_row = exec_lua(function()
      local wins0 = #vim.api.nvim_list_wins()
      local markid = require('gitsigns.async')
        .run(require('gitsigns.actions.preview').preview_hunk_inline)
        :wait()
      assert(markid, 'preview mark not found')

      local ns = vim.api.nvim_get_namespaces().gitsigns_preview_inline
      local marks = vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })
      local details --- @type vim.api.keyset.get_extmark_item[4]?
      for _, mark in ipairs(marks) do
        if mark[1] == markid then
          details = mark[4]
          break
        end
      end
      assert(details and details.virt_lines, 'preview virtual lines not found')

      local function screenline(row, width)
        local chars = {} --- @type string[]
        for col = 1, width do
          chars[#chars + 1] = vim.fn.screenstring(row, col)
        end
        return table.concat(chars)
      end

      local top_row0 --- @type string?
      vim.wait(1000, function()
        vim.cmd('redraw!')
        local row = screenline(1, 24)
        if row:find('alpha', 1, true) then
          top_row0 = row
          return true
        end
      end)

      return wins0,
        #vim.api.nvim_list_wins(),
        #details.virt_lines,
        details.virt_lines_leftcol,
        top_row0
    end)

    eq(wins_before, wins_after)
    eq(1, virt_line_count)
    eq(true, leftcol)
    assert(top_row)
  end)

  it('respects empty statuscolumn output', function()
    setup_test_repo({
      test_file_text = {
        'alpha',
        'local foo = 1',
        'omega',
      },
    })
    local config = vim.deepcopy(test_config)
    config.word_diff = true
    setup_gitsigns(config)
    edit(test_file)

    exec_lua(function()
      vim.wo.statuscolumn = "%{''}"
      vim.wo.signcolumn = 'no'
      vim.wo.number = true
      vim.wo.relativenumber = true
      vim.wo.wrap = false
      vim.api.nvim_buf_set_lines(0, 1, 2, false, { 'local bar = 1' })
      vim.api.nvim_win_set_cursor(0, { 2, 0 })
    end)

    expectf(function()
      local hunk = exec_lua(function()
        return require('gitsigns').get_hunks()[1]
      end)
      assert(hunk and hunk.removed.count == 1)
    end)

    local rendered = exec_lua(function()
      local markid = require('gitsigns.async')
        .run(require('gitsigns.actions.preview').preview_hunk_inline)
        :wait()
      assert(markid)

      local ns = vim.api.nvim_get_namespaces().gitsigns_preview_inline
      local marks = vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })
      for _, mark in ipairs(marks) do
        if mark[1] == markid then
          local chunks = assert(mark[4].virt_lines)[1]
          local text = {} --- @type string[]
          for _, chunk in ipairs(chunks) do
            text[#text + 1] = chunk[1]
          end
          return table.concat(text)
        end
      end
    end)

    assert(rendered)
    eq('local foo = 1', rendered:sub(1, #'local foo = 1'))
  end)

  it('replicates deleted highlight stacks in virtual lines', function()
    require_source_hls()

    setup_test_repo({
      test_file_text = {
        'unchanged',
        'local foo = 1',
      },
    })
    setup_gitsigns(test_config)
    edit(test_file)
    enable_lua_treesitter_on_filetype()

    exec_lua(function()
      vim.api.nvim_buf_set_lines(0, 1, 2, false, { 'local bar = 1' })
      vim.api.nvim_win_set_cursor(0, { 2, 0 })
    end)

    expectf(function()
      local hunk = exec_lua(function()
        return require('gitsigns').get_hunks()[1]
      end)
      assert(hunk and hunk.removed.count == 1 and hunk.added.count == 1)
    end)

    local expected_keyword, expected_diff, virt_line, diff_col = exec_lua(function()
      local Inspect = require('gitsigns.inspect')

      local removed = { 'unchanged', 'local foo = 1' }
      local added = { 'unchanged', 'local bar = 1' }
      local removed_regions = require('gitsigns.diff_int').run_word_diff(
        { removed[2] },
        { added[2] }
      )
      local diff_col = removed_regions[1][3] - 1

      local ns = vim.api.nvim_create_namespace('gitsigns_test_preview')
      local preview_buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, removed)
      vim.bo[preview_buf].filetype = vim.bo.filetype
      vim.bo[preview_buf].tabstop = vim.bo.tabstop
      if vim.bo.syntax ~= '' then
        vim.bo[preview_buf].syntax = vim.bo.syntax
      end
      local ok, parser = pcall(vim.treesitter.get_parser, preview_buf, 'lua')
      assert(ok and parser)
      pcall(parser.parse, parser, true)

      vim.api.nvim_buf_set_extmark(preview_buf, ns, 1, 0, {
        hl_group = 'GitSignsDeleteVirtLn',
        hl_eol = true,
        end_row = 2,
        priority = 1000,
      })
      vim.api.nvim_buf_set_extmark(preview_buf, ns, 1, diff_col, {
        hl_group = 'GitSignsDeleteVirtLnInLine',
        end_col = removed_regions[1][4] - 1,
        end_row = 1,
        priority = 1001,
      })

      local inspected = Inspect.inspect_range(preview_buf, 1, 0, #removed[2])
      local expected_keyword0 = Inspect.hl_stack_at(inspected, 0)
      local expected_diff0 = Inspect.hl_stack_at(inspected, diff_col)

      local markid = require('gitsigns.async')
        .run(require('gitsigns.actions.preview').preview_hunk_inline)
        :wait()
      assert(markid)

      local ns_preview_inline = vim.api.nvim_get_namespaces().gitsigns_preview_inline
      local marks = vim.api.nvim_buf_get_extmarks(0, ns_preview_inline, 0, -1, { details = true })
      local virt_lines --- @type Gitsigns.VirtTextChunk[][]?
      for _, mark in ipairs(marks) do
        if mark[1] == markid then
          virt_lines = assert(mark[4]).virt_lines
          break
        end
      end
      assert(virt_lines)

      vim.api.nvim_buf_delete(preview_buf, { force = true })

      return expected_keyword0, expected_diff0, virt_lines[1], diff_col
    end)

    local actual_keyword = virt_hl_at_col(virt_line, 0)
    local actual_diff = virt_hl_at_col(virt_line, diff_col)

    assert(contains_hl(expected_keyword, '@keyword.lua'))
    assert(contains_hl(actual_keyword, '@keyword.lua'))
    eq(expected_keyword, actual_keyword)
    eq(expected_diff, actual_diff)
  end)

  it('aligns deleted text with signcolumn and relative numbers', function()
    setup_test_repo({
      test_file_text = {
        'alpha',
        'local foo = 1',
        'omega',
      },
    })
    local config = vim.deepcopy(test_config)
    config.word_diff = true
    setup_gitsigns(config)
    edit(test_file)

    exec_lua(function()
      vim.cmd('set number relativenumber signcolumn=auto:3 nowrap')
      vim.api.nvim_buf_set_lines(0, 1, 2, false, { 'local bar = 1' })
      vim.cmd('normal! 2G')
    end)

    expectf(function()
      local deleted_row, changed_row = exec_lua(function()
        require('gitsigns.async')
          .run(require('gitsigns.actions.preview').preview_hunk_inline)
          :wait()
        vim.cmd('redraw!')

        local function screenline(row, width)
          local chars = {} --- @type string[]
          for col = 1, width do
            chars[#chars + 1] = vim.fn.screenstring(row, col)
          end
          return table.concat(chars)
        end

        return screenline(2, 24), screenline(3, 24)
      end)

      local deleted_col = assert(
        deleted_row:find('local', 1, true),
        ('deleted=%q changed=%q'):format(deleted_row, changed_row)
      )
      local changed_col = assert(
        changed_row:find('local', 1, true),
        ('deleted=%q changed=%q'):format(deleted_row, changed_row)
      )
      eq(deleted_col, changed_col)
      eq('  ', deleted_row:sub(1, 2))
      assert(not deleted_row:find('_', 1, true))
      eq(changed_row:sub(3, changed_col - 1), deleted_row:sub(3, deleted_col - 1))
    end)
  end)

  it('scopes inline preview rendering to the active window', function()
    require_window_scoped_deleted_preview()

    setup_test_repo({
      test_file_text = {
        'alpha',
        'local foo = 1',
        'omega',
      },
    })
    local config = vim.deepcopy(test_config)
    config.word_diff = true
    setup_gitsigns(config)
    edit(test_file)

    exec_lua(function()
      vim.api.nvim_buf_set_lines(0, 1, 2, false, { 'local bar = 1' })
      vim.cmd('vsplit')

      local wins = vim.api.nvim_tabpage_list_wins(0)
      local left_win, right_win = wins[1], wins[2]
      assert(left_win and right_win)

      vim.api.nvim_set_current_win(left_win)
      vim.cmd('setlocal nowrap')
      vim.api.nvim_win_set_cursor(left_win, { 2, 0 })

      vim.api.nvim_set_current_win(right_win)
      vim.cmd('setlocal nowrap')
    end)

    expectf(function()
      local left_has_preview, right_has_preview, scoped_wins, preview_marks, left_win = exec_lua(
        function()
          local wins = vim.api.nvim_tabpage_list_wins(0)
          local left_win, right_win = wins[1], wins[2]
          local bufnr = vim.api.nvim_get_current_buf()
          local ns = vim.api.nvim_get_namespaces().gitsigns_preview_inline
          local preview = require('gitsigns.actions.preview')

          vim.api.nvim_set_current_win(left_win)
          require('gitsigns.async').run(preview.preview_hunk_inline):wait()

          local preview_marks0 = 0
          for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })) do
            if assert(mark[4]).virt_lines then
              preview_marks0 = preview_marks0 + 1
            end
          end

          return vim.api.nvim_win_call(left_win, function()
            return preview.has_preview_inline(bufnr)
          end),
            vim.api.nvim_win_call(right_win, function()
              return preview.has_preview_inline(bufnr)
            end),
            vim.api.nvim__ns_get(ns).wins,
            preview_marks0,
            left_win
        end
      )

      eq(true, left_has_preview)
      eq(false, right_has_preview)
      eq(1, preview_marks)
      eq({ left_win }, scoped_wins)
    end)
  end)
end)

describe('popup preview', function()
  before_each(function()
    clear()
    refresh_paths()
  end)

  after_each(function()
    cleanup()
  end)

  it('preserves original highlight priorities in popup lines', function()
    require_source_hls()

    setup_test_repo({
      test_file_text = {
        'unchanged',
        'local foo = 1',
      },
    })
    local config = vim.deepcopy(test_config)
    config.word_diff = true
    setup_gitsigns(config)
    edit(test_file)
    enable_lua_treesitter_on_filetype()

    exec_lua(function()
      vim.api.nvim_buf_set_lines(0, 1, 2, false, { 'local bar = 1' })
      vim.api.nvim_win_set_cursor(0, { 2, 0 })
    end)

    expectf(function()
      local hunk = exec_lua(function()
        return require('gitsigns').get_hunks()[1]
      end)
      assert(hunk and hunk.removed.count == 1 and hunk.added.count == 1)
    end)

    local expected_keyword_priority, actual_keyword_priority, line_priority, diff_priority = exec_lua(
      function()
        require('gitsigns.popup').close('hunk')
        require('gitsigns').preview_hunk()
        local popup_win = assert(require('gitsigns.popup').is_open('hunk'))
        local popup_buf = vim.api.nvim_win_get_buf(popup_win)
        local ns = vim.api.nvim_get_namespaces().gitsigns_popup
        local marks = vim.api.nvim_buf_get_extmarks(popup_buf, ns, 0, -1, { details = true })

        local function mark_contains_hl(hl, group)
          if type(hl) == 'table' then
            return vim.tbl_contains(hl, group)
          end
          return hl == group
        end

        local keyword_priority, line_priority0, diff_priority0
        for _, mark in ipairs(marks) do
          if mark[2] ~= 1 then
            goto continue
          end

          local details = assert(mark[4])
          local start_col = mark[3]
          local end_col = details.end_col or math.huge

          if
            mark_contains_hl(details.hl_group, '@keyword.lua')
            and start_col <= 1
            and end_col > 1
          then
            keyword_priority = details.priority
          elseif details.hl_group == 'GitSignsDeletePreview' then
            line_priority0 = details.priority
          elseif details.hl_group == 'GitSignsDeleteInline' then
            diff_priority0 = details.priority
          end

          ::continue::
        end

        vim.api.nvim_win_close(popup_win, true)

        assert(keyword_priority ~= nil)
        assert(line_priority0 ~= nil)
        assert(diff_priority0 ~= nil)

        return vim.hl.priorities.treesitter, keyword_priority, line_priority0, diff_priority0
      end
    )

    eq(expected_keyword_priority, actual_keyword_priority)
    eq(1000, line_priority)
    eq(1001, diff_priority)
  end)

  it('reuses deleted and added highlight stacks in preview_hunk', function()
    require_source_hls()

    setup_test_repo({
      test_file_text = {
        'unchanged',
        'local foo = 1',
      },
    })
    setup_gitsigns(test_config)
    edit(test_file)
    enable_lua_treesitter_on_filetype()

    exec_lua(function()
      vim.api.nvim_buf_set_lines(0, 1, 2, false, { 'local bar = 1' })
      vim.api.nvim_win_set_cursor(0, { 2, 0 })
    end)

    check({
      status = { head = 'main', added = 0, changed = 1, removed = 0 },
      signs = { changed = 1 },
    })

    local result
    expectf(function()
      result = exec_lua(function()
        local Inspect = require('gitsigns.inspect')

        local function expected_line_hls(line, line_hl, inline_hl, region)
          local preview_buf = vim.api.nvim_create_buf(false, true)
          vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, { line })
          vim.bo[preview_buf].filetype = vim.bo.filetype
          vim.bo[preview_buf].tabstop = vim.bo.tabstop
          if vim.bo.syntax ~= '' then
            vim.bo[preview_buf].syntax = vim.bo.syntax
          end
          local ok, parser = pcall(vim.treesitter.get_parser, preview_buf, 'lua')
          assert(ok and parser)
          pcall(parser.parse, parser, true)

          local ns_preview = vim.api.nvim_create_namespace('gitsigns_test_popup_preview_expected')
          vim.api.nvim_buf_set_extmark(preview_buf, ns_preview, 0, 0, {
            hl_group = line_hl,
            hl_eol = true,
            end_row = 1,
            priority = 1000,
          })
          vim.api.nvim_buf_set_extmark(preview_buf, ns_preview, 0, region[3] - 1, {
            hl_group = inline_hl,
            end_col = region[4] - 1,
            end_row = 0,
            priority = 1001,
          })

          local diff_col = region[3] - 1
          local inspected = Inspect.inspect_range(preview_buf, 0, 0, #line)
          local keyword = Inspect.hl_stack_at(inspected, 0)
          local diff = Inspect.hl_stack_at(inspected, diff_col)

          vim.api.nvim_buf_delete(preview_buf, { force = true })

          return keyword, diff, diff_col
        end

        local removed_line = 'local foo = 1'
        local added_line = 'local bar = 1'
        local removed_regions, added_regions = require('gitsigns.diff_int').run_word_diff(
          { removed_line },
          { added_line }
        )

        local expected_deleted_keyword0, expected_deleted_diff0, deleted_diff_col =
          expected_line_hls(
            removed_line,
            'GitSignsDeletePreview',
            'GitSignsDeleteInline',
            removed_regions[1]
          )
        local expected_added_keyword0, expected_added_diff0, added_diff_col = expected_line_hls(
          added_line,
          'GitSignsAddPreview',
          added_regions[1][2] == 'add' and 'GitSignsAddInline'
            or added_regions[1][2] == 'change' and 'GitSignsChangeInline'
            or 'GitSignsDeleteInline',
          added_regions[1]
        )

        require('gitsigns.popup').close('hunk')
        require('gitsigns').preview_hunk()
        local popup_win = require('gitsigns.popup').is_open('hunk')
        if not popup_win then
          return
        end
        local popup_buf = vim.api.nvim_win_get_buf(popup_win)
        local lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
        local deleted_line = lines[2]
        local added_line0 = lines[3]
        if not deleted_line or not added_line0 then
          return
        end
        assert(deleted_line == '-' .. removed_line, deleted_line)
        assert(added_line0 == '+' .. added_line, added_line0)

        local deleted_actual = Inspect.inspect_range(popup_buf, 1, 0, #removed_line + 1)
        local added_actual = Inspect.inspect_range(popup_buf, 2, 0, #added_line + 1)

        vim.api.nvim_win_close(popup_win, true)

        return {
          expected_deleted_keyword = expected_deleted_keyword0,
          actual_deleted_keyword = Inspect.hl_stack_at(deleted_actual, 1),
          expected_deleted_diff = expected_deleted_diff0,
          actual_deleted_diff = Inspect.hl_stack_at(deleted_actual, deleted_diff_col + 1),
          expected_added_keyword = expected_added_keyword0,
          actual_added_keyword = Inspect.hl_stack_at(added_actual, 1),
          expected_added_diff = expected_added_diff0,
          actual_added_diff = Inspect.hl_stack_at(added_actual, added_diff_col + 1),
        }
      end)
      assert(result)
    end)

    assert(contains_hl(result.expected_deleted_keyword, '@keyword.lua'))
    assert(contains_hl(result.actual_deleted_keyword, '@keyword.lua'))
    assert(contains_hl(result.expected_added_keyword, '@keyword.lua'))
    assert(contains_hl(result.actual_added_keyword, '@keyword.lua'))
    eq(result.expected_deleted_keyword, result.actual_deleted_keyword)
    eq(result.expected_deleted_diff, result.actual_deleted_diff)
    eq(result.expected_added_keyword, result.actual_added_keyword)
    eq(result.expected_added_diff, result.actual_added_diff)
  end)

  it('extends preview_hunk line highlights to the end of the line', function()
    setup_test_repo({
      test_file_text = {
        'unchanged',
        'local foo = 1',
      },
    })
    setup_gitsigns(test_config)
    edit(test_file)

    exec_lua(function()
      vim.api.nvim_buf_set_lines(0, 1, 2, false, { 'local bar = 1' })
      vim.api.nvim_win_set_cursor(0, { 2, 0 })
    end)

    expectf(function()
      local deleted_eol, added_eol = exec_lua(function()
        require('gitsigns.popup').close('hunk')
        require('gitsigns').preview_hunk()
        local popup_win = assert(require('gitsigns.popup').is_open('hunk'))
        local popup_buf = vim.api.nvim_win_get_buf(popup_win)
        local ns = assert(vim.api.nvim_get_namespaces().gitsigns_popup)
        local marks = vim.api.nvim_buf_get_extmarks(popup_buf, ns, 0, -1, { details = true })
        vim.api.nvim_win_close(popup_win, true)

        local deleted_eol0, added_eol0 = false, false
        for _, mark in ipairs(marks) do
          local row = mark[2]
          local col = mark[3]
          local details = assert(mark[4])
          if
            details.hl_group == 'GitSignsDeletePreview'
            and row == 1
            and col == 0
            and details.end_row == 2
            and details.end_col == 0
          then
            deleted_eol0 = true
          elseif
            details.hl_group == 'GitSignsAddPreview'
            and row == 2
            and col == 0
            and details.end_row == 3
            and details.end_col == 0
          then
            added_eol0 = true
          end
        end

        return deleted_eol0, added_eol0
      end)

      eq(true, deleted_eol)
      eq(true, added_eol)
    end)
  end)

  it('keeps delayed source highlights stable across repeated preview_hunk calls', function()
    require_source_hls()

    setup_test_repo({
      test_file_text = {
        'unchanged',
        'local foo = 1',
      },
    })
    setup_gitsigns(test_config)
    edit(test_file)

    exec_lua(function()
      local ns = vim.api.nvim_create_namespace('gitsigns_test_popup_repeat')
      vim.api.nvim_create_autocmd('FileType', {
        group = vim.api.nvim_create_augroup('gitsigns_test_popup_repeat', { clear = true }),
        pattern = 'lua',
        callback = function(args)
          vim.schedule(function()
            if vim.api.nvim_buf_is_valid(args.buf) then
              local row = math.min(1, vim.api.nvim_buf_line_count(args.buf) - 1)
              vim.api.nvim_buf_set_extmark(args.buf, ns, row, 0, {
                end_col = 5,
                end_row = row,
                hl_group = 'ErrorMsg',
                priority = 150,
              })
            end
          end)
        end,
      })

      vim.cmd('syntax on')
      vim.bo.filetype = 'lua'
      vim.api.nvim_buf_set_lines(0, 1, 2, false, { 'local bar = 1' })
      vim.api.nvim_win_set_cursor(0, { 2, 0 })
    end)

    expectf(function()
      local hunk = exec_lua(function()
        return require('gitsigns').get_hunks()[1]
      end)
      assert(hunk and hunk.removed.count == 1 and hunk.added.count == 1)
    end)

    local first_deleted, second_deleted, first_added, second_added = exec_lua(function()
      local Inspect = require('gitsigns.inspect')

      local function popup_stacks()
        require('gitsigns.popup').close('hunk')
        require('gitsigns').preview_hunk()
        local popup_win = assert(require('gitsigns.popup').is_open('hunk'))
        local popup_buf = vim.api.nvim_win_get_buf(popup_win)
        local deleted = Inspect.inspect_range(popup_buf, 1, 0, #'-local foo = 1')
        local added = Inspect.inspect_range(popup_buf, 2, 0, #'+local bar = 1')
        vim.api.nvim_win_close(popup_win, true)
        return Inspect.hl_stack_at(deleted, 1), Inspect.hl_stack_at(added, 1)
      end

      local first_deleted0, first_added0 = popup_stacks()
      local second_deleted0, second_added0 = popup_stacks()
      return first_deleted0, second_deleted0, first_added0, second_added0
    end)

    assert(contains_hl(first_deleted, 'GitSignsDeletePreview'))
    assert(contains_hl(first_deleted, 'ErrorMsg'))
    assert(contains_hl(second_deleted, 'GitSignsDeletePreview'))
    assert(contains_hl(second_deleted, 'ErrorMsg'))
    assert(contains_hl(first_added, 'GitSignsAddPreview'))
    assert(contains_hl(first_added, 'ErrorMsg'))
    assert(contains_hl(second_added, 'GitSignsAddPreview'))
    assert(contains_hl(second_added, 'ErrorMsg'))
    eq(first_deleted, second_deleted)
    eq(first_added, second_added)
  end)

  it('keeps source full-line highlights off the synthetic prefix', function()
    require_source_hls()

    setup_test_repo({
      test_file_text = {
        'unchanged',
        '-- foo',
      },
    })
    local config = vim.deepcopy(test_config)
    config.word_diff = true
    setup_gitsigns(config)
    edit(test_file)

    exec_lua(function()
      local ns = vim.api.nvim_create_namespace('gitsigns_test_popup_prefix')
      vim.api.nvim_create_autocmd('FileType', {
        group = vim.api.nvim_create_augroup('gitsigns_test_popup_prefix', { clear = true }),
        pattern = 'lua',
        callback = function(args)
          vim.api.nvim_buf_set_extmark(args.buf, ns, 1, 0, {
            hl_group = 'ErrorMsg',
            hl_eol = true,
            priority = 150,
          })
        end,
      })

      vim.cmd('syntax on')
      vim.bo.filetype = 'lua'
      vim.api.nvim_buf_set_lines(0, 1, 2, false, { '-- bar' })
      vim.api.nvim_win_set_cursor(0, { 2, 0 })
    end)

    expectf(function()
      local hunk = exec_lua(function()
        return require('gitsigns').get_hunks()[1]
      end)
      assert(hunk and hunk.removed.count == 1 and hunk.added.count == 1)
    end)

    local prefix_stack, text_stack = exec_lua(function()
      local Inspect = require('gitsigns.inspect')

      require('gitsigns.popup').close('hunk')
      require('gitsigns').preview_hunk()
      local popup_win = assert(require('gitsigns.popup').is_open('hunk'))
      local popup_buf = vim.api.nvim_win_get_buf(popup_win)
      local deleted = Inspect.inspect_range(popup_buf, 1, 0, #'--- foo')
      vim.api.nvim_win_close(popup_win, true)

      return Inspect.hl_stack_at(deleted, 0), Inspect.hl_stack_at(deleted, 1)
    end)

    assert(contains_hl(prefix_stack, 'GitSignsDeletePreview'))
    assert(not contains_hl(prefix_stack, 'ErrorMsg'))
    assert(contains_hl(text_stack, 'ErrorMsg'))
  end)

  it('renders staged added lines from the index after unstaged edits above', function()
    setup_test_repo({
      test_file_text = {
        'a',
        'b',
        'c',
        'd',
      },
    })
    setup_gitsigns(test_config)
    edit(test_file)

    exec_lua(function()
      vim.api.nvim_buf_set_lines(0, 2, 3, false, { 'C' })
      vim.cmd('write')
    end)
    git('add', test_file)
    exec_lua(function()
      require('gitsigns').refresh()
    end)

    expectf(function()
      local staged = exec_lua(function()
        local cache = require('gitsigns.cache').cache[vim.api.nvim_get_current_buf()]
        return cache and cache.hunks_staged and #cache.hunks_staged or 0
      end)
      eq(1, staged)
    end)

    exec_lua(function()
      vim.api.nvim_buf_set_lines(0, 0, 0, false, { 'X' })
      vim.api.nvim_win_set_cursor(0, { 4, 0 })
    end)

    expectf(function()
      local title, lines = exec_lua(function()
        require('gitsigns.popup').close('hunk')
        require('gitsigns').preview_hunk()
        local popup_win = assert(require('gitsigns.popup').is_open('hunk'))
        local popup_buf = vim.api.nvim_win_get_buf(popup_win)
        local title0 = assert(vim.api.nvim_buf_get_lines(popup_buf, 0, 1, false)[1])
        local lines0 = vim.api.nvim_buf_get_lines(popup_buf, 1, 3, false)
        vim.api.nvim_win_close(popup_win, true)
        return title0, lines0
      end)

      eq('Hunk 1 of 1', title)
      eq({ '-c', '+C' }, lines)
    end)
  end)

  it('uses unstaged numbering independently from staged hunks', function()
    setup_test_repo({
      test_file_text = {
        'alpha',
        'bravo',
        'charlie',
        'delta',
      },
    })
    setup_gitsigns(test_config)
    edit(test_file)

    exec_lua(function()
      vim.api.nvim_buf_set_lines(0, 1, 2, false, { 'BRAVO' })
      vim.cmd('write')
    end)
    git('add', test_file)
    exec_lua(function()
      require('gitsigns').refresh()
    end)

    expectf(function()
      local unstaged, staged = exec_lua(function()
        local cache = require('gitsigns.cache').cache[vim.api.nvim_get_current_buf()]
        return cache and #cache.hunks or 0,
          cache and cache.hunks_staged and #cache.hunks_staged or 0
      end)
      eq(0, unstaged)
      eq(1, staged)
    end)

    exec_lua(function()
      vim.api.nvim_buf_set_lines(0, 3, 4, false, { 'DELTA' })
      vim.api.nvim_win_set_cursor(0, { 4, 0 })
    end)

    expectf(function()
      local unstaged, staged, title = exec_lua(function()
        local cache = require('gitsigns.cache').cache[vim.api.nvim_get_current_buf()]

        require('gitsigns.popup').close('hunk')
        require('gitsigns').preview_hunk()
        local popup_win = assert(require('gitsigns.popup').is_open('hunk'))
        local popup_buf = vim.api.nvim_win_get_buf(popup_win)
        local line = assert(vim.api.nvim_buf_get_lines(popup_buf, 0, 1, false)[1])
        vim.api.nvim_win_close(popup_win, true)

        return cache and #cache.hunks or 0,
          cache and cache.hunks_staged and #cache.hunks_staged or 0,
          line
      end)

      eq(1, unstaged)
      eq(1, staged)
      eq('Hunk 1 of 1', title)
    end)
  end)

  it('uses greedy hunks for preview_hunk under linematch', function()
    setup_test_repo({
      test_file_text = {
        'alpha',
        'bravo',
        'charlie',
        'delta',
      },
    })
    local config = vim.deepcopy(test_config)
    config.word_diff = false
    config.diff_opts = { linematch = 60 }
    setup_gitsigns(config)
    edit(test_file)

    exec_lua(function()
      vim.api.nvim_buf_set_lines(0, 0, 4, false, {
        'BRAVO',
        'CHARLIE',
        'delta',
        'alpha',
      })
      vim.api.nvim_win_set_cursor(0, { 2, 0 })
    end)

    expectf(function()
      local regular_count, greedy_count = exec_lua(function()
        local async = require('gitsigns.async')
        local bcache = require('gitsigns.cache').cache[vim.api.nvim_get_current_buf()]
        local regular, greedy

        async
          .run(function()
            regular = bcache:get_hunks(false, false)
            greedy = bcache:get_hunks(true, false)
          end)
          :wait()

        return regular and #regular or 0, greedy and #greedy or 0
      end)

      eq(4, regular_count)
      eq(2, greedy_count)
    end)

    local lines = exec_lua(function()
      require('gitsigns.popup').close('hunk')
      require('gitsigns').preview_hunk()
      local popup_win = assert(require('gitsigns.popup').is_open('hunk'))
      local popup_buf = vim.api.nvim_win_get_buf(popup_win)
      local lines0 = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
      vim.api.nvim_win_close(popup_win, true)
      return lines0
    end)

    eq({
      'Hunk 1 of 2',
      '-alpha',
      '-bravo',
      '-charlie',
      '+BRAVO',
      '+CHARLIE',
    }, lines)
  end)
end)

describe('show_deleted', function()
  before_each(function()
    clear()
    refresh_paths()
  end)

  after_each(function()
    cleanup()
  end)

  it('prepares deleted preview metadata without eager capture', function()
    require_window_scoped_deleted_preview()

    setup_test_repo({
      test_file_text = {
        'unchanged',
        'local foo = 1',
      },
    })
    local config = vim.deepcopy(test_config)
    config.show_deleted = true
    config.word_diff = true
    setup_gitsigns(config)
    edit(test_file)
    exec_lua(function()
      vim.api.nvim_buf_set_lines(0, 1, 2, false, { 'local bar = 1' })
    end)

    expectf(function()
      local hunk = exec_lua(function()
        return require('gitsigns').get_hunks()[1]
      end)
      assert(hunk and hunk.removed.count == 1)
    end)

    local calls = exec_lua(function()
      local bufnr = vim.api.nvim_get_current_buf()
      local DeletedPreview = require('gitsigns.deleted_preview')
      local HunkPreview = require('gitsigns.hunk_preview')
      local orig = HunkPreview.prepare_removed_source
      local count = 0

      HunkPreview.prepare_removed_source = function(...)
        count = count + 1
        return orig(...)
      end

      local ok, err = pcall(DeletedPreview.prepare, bufnr)
      HunkPreview.prepare_removed_source = orig

      assert(ok, err)
      return count
    end)

    eq(0, calls)
  end)

  it('keeps existing deleted lines visible while lazy capture is pending', function()
    require_window_scoped_deleted_preview()

    setup_test_repo({
      test_file_text = {
        'unchanged',
        'local foo = 1',
      },
    })
    local config = vim.deepcopy(test_config)
    config.show_deleted = true
    config.word_diff = true
    setup_gitsigns(config)
    edit(test_file)
    exec_lua(function()
      vim.api.nvim_buf_set_lines(0, 1, 2, false, { 'local bar = 1' })
    end)

    expectf(function()
      local clears, scheduled, rendered = exec_lua(function()
        local bufnr = vim.api.nvim_get_current_buf()
        local winid = vim.api.nvim_get_current_win()
        local DeletedPreview = require('gitsigns.deleted_preview')
        local orig_clear = vim.api.nvim_buf_clear_namespace
        local orig_schedule = vim.schedule
        local clear_calls = 0
        local did_schedule = false

        vim.schedule = function(_)
          did_schedule = true
        end

        vim.api.nvim_buf_clear_namespace = function(...)
          clear_calls = clear_calls + 1
          return orig_clear(...)
        end

        local ok, result = pcall(function()
          DeletedPreview.prepare(bufnr)
          return DeletedPreview.on_win(winid, bufnr, 1, vim.api.nvim_buf_line_count(bufnr))
        end)

        vim.api.nvim_buf_clear_namespace = orig_clear
        vim.schedule = orig_schedule

        assert(ok, result)
        return clear_calls, did_schedule, result
      end)

      eq(0, clears)
      eq(true, scheduled)
      eq(false, rendered)
    end)
  end)

  it('renders deleted lines via the decoration provider', function()
    setup_test_repo({
      test_file_text = {
        'unchanged',
        'local foo = 1',
      },
    })
    local config = vim.deepcopy(test_config)
    config.show_deleted = true
    config.word_diff = true
    setup_gitsigns(config)
    edit(test_file)
    exec_lua(function()
      vim.api.nvim_buf_set_lines(0, 1, 2, false, { 'local bar = 1' })
    end)

    expectf(function()
      local rows = exec_lua(function()
        vim.cmd('redraw!')

        local function screenline(row, width)
          local chars = {} --- @type string[]
          for col = 1, width do
            chars[#chars + 1] = vim.fn.screenstring(row, col)
          end
          return table.concat(chars)
        end

        local rows0 = {} --- @type string[]
        for row = 1, 4 do
          rows0[row] = screenline(row, 24)
        end

        return rows0
      end)

      local deleted_row, changed_row
      for _, row in ipairs(rows) do
        if row:find('local foo = 1', 1, true) then
          deleted_row = row
        elseif row:find('local bar = 1', 1, true) then
          changed_row = row
        end
      end

      local deleted_col = assert(deleted_row, ('rows=%s'):format(vim.inspect(rows)))
        and assert(deleted_row:find('local', 1, true), ('rows=%s'):format(vim.inspect(rows)))
      local changed_col = assert(changed_row, ('rows=%s'):format(vim.inspect(rows)))
        and assert(changed_row:find('local', 1, true), ('rows=%s'):format(vim.inspect(rows)))
      eq(deleted_col, changed_col)
      assert(deleted_row:find('local foo = 1', 1, true))
      assert(changed_row:find('local bar = 1', 1, true))
    end)
  end)

  it('refreshes deleted preview captures when word_diff changes', function()
    require_window_scoped_deleted_preview()

    setup_test_repo({
      test_file_text = {
        'unchanged',
        'local foo = 1',
      },
    })
    local config = vim.deepcopy(test_config)
    config.show_deleted = true
    config.word_diff = true
    setup_gitsigns(config)
    edit(test_file)

    exec_lua(function()
      vim.api.nvim_buf_set_lines(0, 1, 2, false, { 'local bar = 1' })
    end)

    expectf(function()
      exec_lua(function()
        vim.cmd('redraw!')
      end)
      eq(true, deleted_preview_has_hl('GitSignsDeleteVirtLnInLine'))
    end)

    exec_lua(function()
      require('gitsigns').toggle_word_diff(false)
    end)

    expectf(function()
      exec_lua(function()
        vim.cmd('redraw!')
      end)
      eq(true, deleted_preview_has_hl('GitSignsDeleteVirtLn'))
      eq(false, deleted_preview_has_hl('GitSignsDeleteVirtLnInLine'))
    end)
  end)

  it('aligns deleted text with signcolumn and relative numbers', function()
    require_window_scoped_deleted_preview()

    setup_test_repo({
      test_file_text = {
        'alpha',
        'local foo = 1',
        'omega',
      },
    })
    local config = vim.deepcopy(test_config)
    config.show_deleted = true
    config.word_diff = true
    setup_gitsigns(config)
    edit(test_file)

    exec_lua(function()
      vim.cmd('set number relativenumber signcolumn=auto:3 nowrap')
      vim.api.nvim_buf_set_lines(0, 1, 2, false, { 'local bar = 1' })
      vim.cmd('normal! 3G')
    end)

    expectf(function()
      local deleted_row, changed_row = exec_lua(function()
        vim.cmd('redraw!')

        local function screenline(row, width)
          local chars = {} --- @type string[]
          for col = 1, width do
            chars[#chars + 1] = vim.fn.screenstring(row, col)
          end
          return table.concat(chars)
        end

        return screenline(2, 24), screenline(3, 24)
      end)

      local deleted_col = assert(deleted_row:find('local', 1, true))
      local changed_col = assert(changed_row:find('local', 1, true))
      eq(deleted_col, changed_col)
      eq('  ', deleted_row:sub(1, 2))
      assert(not deleted_row:find('_', 1, true))
      eq(changed_row:sub(3, changed_col - 1), deleted_row:sub(3, deleted_col - 1))
      assert(deleted_row:find('1 local foo = 1', 1, true))
    end)
  end)

  it('uses window-local prefixes for each window showing the buffer', function()
    setup_test_repo({
      test_file_text = {
        'alpha',
        'local foo = 1',
        'omega',
      },
    })
    local config = vim.deepcopy(test_config)
    config.show_deleted = true
    config.word_diff = true
    setup_gitsigns(config)
    edit(test_file)

    exec_lua(function()
      vim.api.nvim_buf_set_lines(0, 1, 2, false, { 'local bar = 1' })
      vim.cmd('vsplit')

      local wins = vim.api.nvim_tabpage_list_wins(0)
      local left_win, right_win = wins[1], wins[2]
      assert(left_win and right_win)

      vim.api.nvim_set_current_win(left_win)
      vim.cmd('setlocal number relativenumber signcolumn=auto:3 nowrap')

      vim.api.nvim_set_current_win(right_win)
      vim.cmd('setlocal nonumber norelativenumber signcolumn=no nowrap')
    end)

    expectf(function()
      local left_deleted, left_changed, right_deleted, right_changed = exec_lua(function()
        vim.cmd('redraw!')

        local wins = vim.api.nvim_tabpage_list_wins(0)
        local left_win, right_win = wins[1], wins[2]

        local function screenline(winid, row, width)
          local pos = vim.fn.win_screenpos(winid)
          local screen_row = pos[1] + row - 1
          local screen_col = pos[2]
          local chars = {} --- @type string[]
          for col = screen_col, screen_col + width - 1 do
            chars[#chars + 1] = vim.fn.screenstring(screen_row, col)
          end
          return table.concat(chars)
        end

        return screenline(left_win, 2, 28),
          screenline(left_win, 3, 28),
          screenline(right_win, 2, 28),
          screenline(right_win, 3, 28)
      end)

      local left_deleted_col = assert(left_deleted:find('local', 1, true))
      local left_changed_col = assert(left_changed:find('local', 1, true))
      local right_deleted_col = assert(right_deleted:find('local', 1, true))
      local right_changed_col = assert(right_changed:find('local', 1, true))

      eq(left_deleted_col, left_changed_col)
      eq(right_deleted_col, right_changed_col)
      assert(left_deleted_col > right_deleted_col)
    end)
  end)

  it('clears deleted preview extmarks when a window switches buffers', function()
    require_window_scoped_deleted_preview()

    setup_test_repo({
      test_file_text = {
        'unchanged',
        'local foo = 1',
      },
    })
    local config = vim.deepcopy(test_config)
    config.show_deleted = true
    config.word_diff = true
    setup_gitsigns(config)
    edit(test_file)

    exec_lua(function()
      vim.api.nvim_buf_set_lines(0, 1, 2, false, { 'local bar = 1' })
    end)

    local old_bufnr = exec_lua(function()
      return vim.api.nvim_get_current_buf()
    end)

    expectf(function()
      exec_lua(function()
        vim.cmd('redraw!')
      end)
      assert(count_deleted_preview_marks(old_bufnr) > 0)
    end)

    exec_lua(function()
      vim.cmd('enew')
      vim.cmd('redraw!')
    end)

    expectf(function()
      eq(0, count_deleted_preview_marks(old_bufnr))
    end)
  end)

  it('clears deleted preview extmarks when the buffer becomes clean', function()
    require_window_scoped_deleted_preview()

    setup_test_repo({
      test_file_text = {
        'unchanged',
        'local foo = 1',
      },
    })
    local config = vim.deepcopy(test_config)
    config.show_deleted = true
    config.word_diff = true
    setup_gitsigns(config)
    edit(test_file)

    exec_lua(function()
      vim.api.nvim_buf_set_lines(0, 1, 2, false, { 'local bar = 1' })
    end)

    local bufnr = exec_lua(function()
      return vim.api.nvim_get_current_buf()
    end)

    expectf(function()
      exec_lua(function()
        vim.cmd('redraw!')
      end)
      assert(count_deleted_preview_marks(bufnr) > 0)
    end)

    exec_lua(function()
      vim.api.nvim_buf_set_lines(0, 1, 2, false, { 'local foo = 1' })
    end)

    expectf(function()
      local hunks = exec_lua(function()
        vim.cmd('redraw!')
        return require('gitsigns').get_hunks()
      end)

      eq(0, #hunks)
      eq(0, count_deleted_preview_marks(bufnr))
    end)
  end)

  it('keeps delayed source highlights across multiple removed hunks', function()
    require_source_hls()

    setup_test_repo({
      test_file_text = {
        'header',
        'local foo = 1',
        'middle',
        'local baz = 2',
      },
    })
    local config = vim.deepcopy(test_config)
    config.show_deleted = true
    config.word_diff = true
    setup_gitsigns(config)
    edit(test_file)

    exec_lua(function()
      local ns = vim.api.nvim_create_namespace('gitsigns_test_show_deleted_multi')
      vim.api.nvim_create_autocmd('FileType', {
        group = vim.api.nvim_create_augroup('gitsigns_test_show_deleted_multi', { clear = true }),
        pattern = 'lua',
        callback = function(args)
          vim.api.nvim_buf_set_extmark(args.buf, ns, 1, 0, {
            end_col = 5,
            end_row = 1,
            hl_group = 'ErrorMsg',
            priority = 150,
          })
          vim.schedule(function()
            if vim.api.nvim_buf_is_valid(args.buf) then
              vim.api.nvim_buf_set_extmark(args.buf, ns, 3, 0, {
                end_col = 5,
                end_row = 3,
                hl_group = 'ErrorMsg',
                priority = 150,
              })
            end
          end)
        end,
      })

      vim.cmd('syntax on')
      vim.bo.filetype = 'lua'
      vim.api.nvim_buf_set_lines(0, 1, 2, false, { 'local bar = 1' })
      vim.api.nvim_buf_set_lines(0, 3, 4, false, { 'local qux = 2' })
    end)

    expectf(function()
      local hunks = exec_lua(function()
        return require('gitsigns').get_hunks()
      end)
      eq(2, #hunks)
    end)

    local first_stack, second_stack = exec_lua(function()
      local function contains_hl0(hl, group)
        if type(hl) == 'table' then
          return vim.tbl_contains(hl, group)
        end
        return hl == group
      end

      local function collect_marks()
        local marks = {} --- @type vim.api.keyset.get_extmark_item[]
        for _, ns in pairs(vim.api.nvim_get_namespaces()) do
          for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })) do
            local details = mark[4]
            if details and details.virt_lines and details.virt_lines_leftcol then
              local chunks = details.virt_lines[1]
              if chunks then
                for _, chunk in ipairs(chunks) do
                  if contains_hl0(chunk[2], 'GitSignsDeleteVirtLn') then
                    marks[#marks + 1] = mark
                    break
                  end
                end
              end
            end
          end
        end
        table.sort(marks, function(a, b)
          return a[2] < b[2]
        end)
        return marks
      end

      local marks --- @type vim.api.keyset.get_extmark_item[]?
      vim.wait(1000, function()
        vim.cmd('redraw!')
        marks = collect_marks()
        return #marks >= 2
      end)
      assert(marks and #marks >= 2, vim.inspect(marks))

      local function collect_hls(mark)
        local seen = {} --- @type table<string, true>
        for _, chunk in ipairs(assert(assert(mark[4]).virt_lines)[1]) do
          local hl = chunk[2]
          if type(hl) == 'table' then
            for _, name in ipairs(hl) do
              seen[name] = true
            end
          elseif hl and hl ~= '' then
            seen[hl] = true
          end
        end

        local ret = {} --- @type string[]
        for hl in pairs(seen) do
          ret[#ret + 1] = hl
        end
        table.sort(ret)
        return ret
      end

      return collect_hls(assert(marks[1])), collect_hls(assert(marks[2]))
    end)

    assert(contains_hl(first_stack, 'ErrorMsg'))
    assert(contains_hl(second_stack, 'ErrorMsg'))
  end)
end)

describe('hunk preview source buffers', function()
  before_each(function()
    clear()
    refresh_paths()
  end)

  after_each(function()
    cleanup()
  end)

  it('clears cached syntax when the source syntax is cleared', function()
    setup_test_repo()
    setup_gitsigns(test_config)
    edit(test_file)

    expectf(function()
      local before_syntax, after_syntax = exec_lua(function()
        local HunkPreview = require('gitsigns.hunk_preview')
        local source_cache = {} --- @type table<string, Gitsigns.HunkPreview.SourceBuf>
        local bufnr = vim.api.nvim_get_current_buf()

        vim.bo[0].syntax = 'lua'
        local _, cleanup = HunkPreview.prepare_removed_source(bufnr, false, source_cache)
        cleanup()

        local cached_bufnr = assert(source_cache['removed:unstaged']).bufnr
        local before = vim.bo[cached_bufnr].syntax

        vim.bo[0].syntax = ''
        local _, cleanup2 = HunkPreview.prepare_removed_source(bufnr, false, source_cache)
        cleanup2()

        local after = vim.bo[cached_bufnr].syntax
        pcall(vim.api.nvim_buf_delete, cached_bufnr, { force = true })
        return before, after
      end)

      eq('lua', before_syntax)
      eq('', after_syntax)
    end)
  end)

  it('recreates cached source buffers when the source text changes', function()
    setup_test_repo()
    setup_gitsigns(test_config)
    edit(test_file)

    expectf(function()
      local first_valid, second_valid, same_buf, stale_marks = exec_lua(function()
        local HunkPreview = require('gitsigns.hunk_preview')
        local bcache = require('gitsigns.cache').cache[vim.api.nvim_get_current_buf()]
        assert(bcache and bcache.compare_text)

        local source_cache = {} --- @type table<string, Gitsigns.HunkPreview.SourceBuf>
        local bufnr = vim.api.nvim_get_current_buf()
        local ns = vim.api.nvim_create_namespace('gitsigns_test_source_cache')

        local _, cleanup = HunkPreview.prepare_removed_source(bufnr, false, source_cache)
        cleanup()

        local first = assert(source_cache['removed:unstaged']).bufnr
        vim.api.nvim_buf_set_extmark(first, ns, 0, 0, {
          end_col = 1,
          hl_group = 'ErrorMsg',
        })

        bcache.compare_text = { 'replacement line' }

        local _, cleanup2 = HunkPreview.prepare_removed_source(bufnr, false, source_cache)
        cleanup2()

        local second = assert(source_cache['removed:unstaged']).bufnr
        local marks = vim.api.nvim_buf_get_extmarks(second, ns, 0, -1, {})

        local first_valid0 = vim.api.nvim_buf_is_valid(first)
        local second_valid0 = vim.api.nvim_buf_is_valid(second)
        pcall(vim.api.nvim_buf_delete, second, { force = true })

        return first_valid0, second_valid0, first == second, #marks
      end)

      eq(false, first_valid)
      eq(true, second_valid)
      eq(false, same_buf)
      eq(0, stale_marks)
    end)
  end)
end)
