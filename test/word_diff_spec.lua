local helpers = require('test.gs_helpers')

local exec_lua = helpers.exec_lua
local eq = helpers.eq
local setup_test_repo = helpers.setup_test_repo
local setup_gitsigns = helpers.setup_gitsigns
local test_config = helpers.test_config
local edit = helpers.edit
local test_file = helpers.test_file
local clear = helpers.clear
local cleanup = helpers.cleanup
local expectf = helpers.expectf

helpers.env()

describe('word diff', function()
  before_each(function()
    clear()
    setup_gitsigns()
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
  end)

  after_each(function()
    cleanup()
  end)

  it('word diff aligns highlights after multibyte characters', function()
    if helpers.fn.has('nvim-0.11') == 0 then
      pending('requires Neovim 0.11+')
    end
    setup_test_repo({ test_file_text = { 'éx' } })
    local config = vim.deepcopy(test_config)
    config.word_diff = true
    setup_gitsigns(config)
    edit(test_file)

    exec_lua(function()
      vim.api.nvim_buf_set_lines(0, 0, 1, false, { 'éy' })
    end)

    exec_lua(function()
      require('gitsigns').refresh()
    end)

    expectf(function()
      local hunks = exec_lua("return require('gitsigns').get_hunks()")
      eq(1, #hunks)
    end)

    exec_lua(function()
      require('gitsigns').preview_hunk_inline()
    end)

    local start_col, end_col = exec_lua(function()
      local ns = vim.api.nvim_get_namespaces().gitsigns_preview_inline
      local marks = vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })
      local start_col0, end_col0 --- @type integer?, integer?
      for _, mark in ipairs(marks) do
        local details = mark[4]
        if details and details.hl_group == 'GitSignsChangeInline' then
          start_col0 = mark[3]
          end_col0 = details.end_col
          break
        end
      end
      return start_col0, end_col0
    end)

    local expected_start, expected_end = exec_lua(function()
      local line = assert(vim.api.nvim_buf_get_lines(0, 0, 1, false)[1])
      -- Use UTF-32 indexes so we can count characters.
      return vim.str_byteindex(line, 'utf-32', 1), vim.str_byteindex(line, 'utf-32', 2)
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

    local deleted_marks = exec_lua(function()
      local async = require('gitsigns.async')
      local winid = async
        .run(function()
          return require('gitsigns.actions.preview').preview_hunk_inline()
        end)
        :wait()
      assert(winid, 'preview window not found')
      local buf = vim.api.nvim_win_get_buf(winid)
      local ns = vim.api.nvim_get_namespaces().gitsigns_preview_inline
      return #vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
    end)

    eq(2, deleted_marks)
  end)
end)
