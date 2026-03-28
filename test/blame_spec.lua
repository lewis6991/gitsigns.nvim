local helpers = require('test.gs_helpers')

local setup_gitsigns = helpers.setup_gitsigns
local feed = helpers.feed
local edit = helpers.edit
local exec_lua = helpers.exec_lua
local fn = helpers.fn
local test_config = helpers.test_config
local clear = helpers.clear
local expectf = helpers.expectf
local setup_test_repo = helpers.setup_test_repo
local eq = helpers.eq
local check = helpers.check
local git = helpers.git
local write_to_file = helpers.write_to_file
local scratch --- @type string
local test_file --- @type string

helpers.env()

local function refresh_paths()
  scratch = helpers.scratch
  test_file = helpers.test_file
end

local function require_source_hls()
  if fn.has('nvim-0.12') == 0 then
    pending('requires Neovim 0.12+')
  end
end

local function enable_lua_treesitter_on_filetype()
  exec_lua(function()
    vim.api.nvim_create_autocmd('FileType', {
      group = vim.api.nvim_create_augroup('gitsigns_blame_treesitter', { clear = true }),
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

describe('blame', function()
  before_each(function()
    clear()
    refresh_paths()
    helpers.chdir_tmp()
    helpers.setup_path()
  end)

  it('keeps cursor line on reblame', function()
    setup_gitsigns(test_config)
    setup_test_repo({
      test_file_text = { 'one', 'two', 'three', 'four', 'five' },
    })
    helpers.write_to_file(test_file, { 'ONE', 'two', 'three', 'four', 'five' })
    helpers.git('add', test_file)
    helpers.git('commit', '-m', 'second commit')

    edit(test_file)
    check({
      status = { head = 'main', added = 0, changed = 0, removed = 0 },
      signs = {},
    })
    exec_lua(function()
      local async = require('gitsigns.async')
      async.run(require('gitsigns.actions.blame').blame):raise_on_error()
    end)

    eq(
      true,
      exec_lua(function()
        return vim.wait(10000, function()
          return vim.bo.filetype == 'gitsigns-blame'
        end)
      end)
    )

    local initial_blame_bufname = exec_lua('return vim.api.nvim_buf_get_name(0)')

    feed('3G')
    feed('r')

    eq(
      true,
      exec_lua(function(initial_name)
        return vim.wait(5000, function()
          return vim.bo.filetype == 'gitsigns-blame'
            and vim.api.nvim_buf_get_name(0) ~= initial_name
        end)
      end, initial_blame_bufname)
    )

    eq({ 3, 0 }, helpers.api.nvim_win_get_cursor(0))
    eq('gitsigns-blame', exec_lua('return vim.bo.filetype'))
  end)

  it('uses a repo-relative path when running blame', function()
    local args = exec_lua(function()
      local blame = require('gitsigns.git.blame')

      local captured_args
      local obj = {
        file = 'C:/msys64/home/User/.dotfiles/.config/nvim/lua/mappings.lua',
        relpath = '.config/nvim/lua/mappings.lua',
        object_name = ('a'):rep(40),
        repo = {
          abbrev_head = 'main',
          toplevel = 'C:/msys64/home/User/.dotfiles',
          command = function(_, argv, spec)
            captured_args = vim.deepcopy(argv)
            spec.stdout(
              nil,
              table.concat({
                ('a'):rep(40) .. ' 1 1 1',
                'author tester',
                'author-mail <tester@example.com>',
                'author-time 0',
                'author-tz +0000',
                'committer tester',
                'committer-mail <tester@example.com>',
                'committer-time 0',
                'committer-tz +0000',
                'summary init',
                'filename .config/nvim/lua/mappings.lua',
                '',
              }, '\n')
            )
            return {}, nil, 0
          end,
        },
      }

      blame.run_blame(obj, { 'line' }, 1, nil, {})

      return captured_args
    end)

    eq('--', args[#args - 1])
    eq('.config/nvim/lua/mappings.lua', args[#args])
  end)

  it('blames a tracked file in a nested path', function()
    helpers.git_init_scratch()
    setup_gitsigns(test_config)

    local relpath = '.config/nvim/lua/mappings.lua'
    local file = scratch .. '/' .. relpath

    write_to_file(file, { 'hello', 'world' })
    git('add', file)
    git('commit', '-m', 'add nested mappings')

    edit(file)

    expectf(function()
      return exec_lua(function()
        return vim.b.gitsigns_status_dict.gitdir ~= nil
      end)
    end)

    local result = exec_lua(function(file0)
      local async = require('gitsigns.async')
      return async
        .run(function()
          local Git = require('gitsigns.git')
          local encoding = vim.bo.fileencoding
          if encoding == '' then
            encoding = 'utf-8'
          end

          local obj = assert(Git.Obj.new(file0, nil, encoding))
          local blame_entries = obj:run_blame(nil, 1, nil, {})
          local blame_info = blame_entries and blame_entries[1]
          obj:close()

          return {
            relpath = obj.relpath,
            file = obj.file,
            filename = blame_info and blame_info.filename or '',
            sha = blame_info and blame_info.commit and blame_info.commit.sha or '',
          }
        end)
        :wait(5000)
    end, file)

    eq(relpath, result.relpath)
    eq(false, result.file == result.relpath)
    eq(relpath, result.filename)
    eq(false, result.sha == '')
  end)

  it('reuses source highlight stacks in the full blame popup hunk', function()
    require_source_hls()

    setup_test_repo({
      test_file_text = {
        'local foo = 1',
      },
    })

    helpers.write_to_file(test_file, {
      'local bar = 1',
    })
    helpers.git('add', test_file)
    helpers.git('commit', '-m', 'rename foo')

    local config = vim.deepcopy(test_config)
    config.gh = true
    setup_gitsigns(config)
    edit(test_file)
    enable_lua_treesitter_on_filetype()

    check({
      status = { head = 'main', added = 0, changed = 0, removed = 0 },
      signs = {},
    })

    exec_lua(function()
      local async = require('gitsigns.async')

      package.loaded['gitsigns.gh'] = {
        commit_url = function()
          return 'https://example.test/commit'
        end,
        create_pr_linespec = function()
          return { { '#1 ', 'Title', 'https://example.test/pr/1' } }
        end,
      }

      async.run(require('gitsigns.actions.blame_line'), { full = true }):wait()
    end)

    expectf(function()
      local result = exec_lua(function()
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

          local ns_preview = vim.api.nvim_create_namespace('gitsigns_test_blame_expected')
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
          local inspected = require('gitsigns.inspect').inspect_range(preview_buf, 0, 0, #line)
          local keyword = require('gitsigns.inspect').hl_stack_at(inspected, 0)
          local diff = require('gitsigns.inspect').hl_stack_at(inspected, diff_col)

          vim.api.nvim_buf_delete(preview_buf, { force = true })

          return keyword, diff, diff_col
        end

        local popup_win = require('gitsigns.popup').is_open('blame')
        if not popup_win then
          return
        end

        local popup_buf = vim.api.nvim_win_get_buf(popup_win)
        local lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
        local deleted_row, added_row

        for i, line in ipairs(lines) do
          if line == '-local foo = 1' then
            deleted_row = i - 1
          elseif line == '+local bar = 1' then
            added_row = i - 1
          end
        end

        if deleted_row == nil or added_row == nil then
          return
        end

        local Inspect = require('gitsigns.inspect')
        local removed_regions, added_regions = require('gitsigns.diff_int').run_word_diff(
          { 'local foo = 1' },
          { 'local bar = 1' }
        )
        local expected_deleted_keyword, expected_deleted_diff, deleted_diff_col = expected_line_hls(
          'local foo = 1',
          'GitSignsDeletePreview',
          'GitSignsDeleteInline',
          removed_regions[1]
        )
        local expected_added_keyword, expected_added_diff, added_diff_col = expected_line_hls(
          'local bar = 1',
          'GitSignsAddPreview',
          added_regions[1][2] == 'add' and 'GitSignsAddInline'
            or added_regions[1][2] == 'change' and 'GitSignsChangeInline'
            or 'GitSignsDeleteInline',
          added_regions[1]
        )
        local deleted = Inspect.inspect_range(popup_buf, deleted_row, 0, #'-local foo = 1')
        local added = Inspect.inspect_range(popup_buf, added_row, 0, #'+local bar = 1')

        return {
          title = lines[1],
          expected_deleted_keyword = expected_deleted_keyword,
          actual_deleted_keyword = Inspect.hl_stack_at(deleted, 1),
          expected_deleted_diff = expected_deleted_diff,
          actual_deleted_diff = Inspect.hl_stack_at(deleted, deleted_diff_col + 1),
          expected_added_keyword = expected_added_keyword,
          actual_added_keyword = Inspect.hl_stack_at(added, 1),
          expected_added_diff = expected_added_diff,
          actual_added_diff = Inspect.hl_stack_at(added, added_diff_col + 1),
        }
      end)

      assert(result)
      eq(result.expected_deleted_keyword, result.actual_deleted_keyword)
      eq(result.expected_deleted_diff, result.actual_deleted_diff)
      eq(result.expected_added_keyword, result.actual_added_keyword)
      eq(result.expected_added_diff, result.actual_added_diff)
      assert(result.title:find('#1', 1, true))
    end)
  end)

  it('extends full blame popup line highlights to the end of the line', function()
    setup_test_repo({
      test_file_text = {
        'local foo = 1',
      },
    })

    helpers.write_to_file(test_file, {
      'local bar = 1',
    })
    helpers.git('add', test_file)
    helpers.git('commit', '-m', 'rename foo')

    local config = vim.deepcopy(test_config)
    config.gh = true
    setup_gitsigns(config)
    edit(test_file)
    check({
      status = { head = 'main', added = 0, changed = 0, removed = 0 },
      signs = {},
    })

    exec_lua(function()
      local async = require('gitsigns.async')

      package.loaded['gitsigns.gh'] = {
        commit_url = function()
          return 'https://example.test/commit'
        end,
        create_pr_linespec = function()
          return { { '#1 ', 'Title', 'https://example.test/pr/1' } }
        end,
      }

      async.run(require('gitsigns.actions.blame_line'), { full = true }):wait()
    end)

    local result
    expectf(function()
      result = exec_lua(function()
        local popup_win = require('gitsigns.popup').is_open('blame')
        if not popup_win then
          return
        end
        local popup_buf = vim.api.nvim_win_get_buf(popup_win)
        local lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
        local ns = assert(vim.api.nvim_get_namespaces().gitsigns_popup)
        local marks = vim.api.nvim_buf_get_extmarks(popup_buf, ns, 0, -1, { details = true })

        local deleted_row, added_row
        for i, line in ipairs(lines) do
          if line == '-local foo = 1' then
            deleted_row = i - 1
          elseif line == '+local bar = 1' then
            added_row = i - 1
          end
        end

        if deleted_row == nil or added_row == nil then
          return
        end

        local deleted_eol0, added_eol0 = false, false
        for _, mark in ipairs(marks) do
          local row = mark[2]
          local col = mark[3]
          local details = assert(mark[4])
          if
            details.hl_group == 'GitSignsDeletePreview'
            and row == deleted_row
            and col == 0
            and details.end_row == deleted_row + 1
            and details.end_col == 0
          then
            deleted_eol0 = true
          elseif
            details.hl_group == 'GitSignsAddPreview'
            and row == added_row
            and col == 0
            and details.end_row == added_row + 1
            and details.end_col == 0
          then
            added_eol0 = true
          end
        end

        return {
          deleted_eol = deleted_eol0,
          added_eol = added_eol0,
        }
      end)

      assert(result and result.deleted_eol and result.added_eol)
    end)
  end)
end)
