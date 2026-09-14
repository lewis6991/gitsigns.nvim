local helpers = require('test.gs_helpers')
local api = helpers.api
local eq = helpers.eq
local exec_lua = helpers.exec_lua
local git = helpers.git

helpers.env()

--- @param action 'diff'|'show_commit'
--- @param revision? string
--- @param paths? string[]
local function open_panel(action, revision, paths)
  exec_lua(function(opts)
    local done = false
    require('gitsigns')[opts.action](opts.revision, opts.paths, function(err)
      assert(not err, err)
      done = true
    end)

    assert(vim.wait(5000, function()
      return done
    end))
  end, { action = action, revision = revision, paths = paths })
  eq('gitsigns-diff', exec_lua('return vim.bo.filetype'))
end

--- @param revision? string
--- @param paths? string[]
local function open_diff(revision, paths)
  open_panel('diff', revision, paths)
end

--- @param revision? string
local function open_commit(revision)
  open_panel('show_commit', revision)
end

--- @param args string
local function open_diff_command(args)
  api.nvim_command('Gitsigns diff ' .. args)
  helpers.expectf(function()
    eq('gitsigns-diff', exec_lua('return vim.bo.filetype'))
  end)
end

--- @param ... string
--- @return string[]
local function git_output(...)
  return helpers.fn.systemlist(vim.list_extend({ 'git', '-C', helpers.scratch }, { ... }))
end

--- @return table
local function diff_state()
  return exec_lua(function()
    local wins = vim.api.nvim_tabpage_list_wins(0)
    table.sort(wins, function(a, b)
      return vim.api.nvim_win_get_position(a)[2] < vim.api.nvim_win_get_position(b)[2]
    end)
    local result = {}
    for _, win in ipairs(wins) do
      if vim.wo[win].diff then
        local buf = vim.api.nvim_win_get_buf(win)
        result[#result + 1] = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        if vim.bo[buf].buftype ~= '' then
          assert(not vim.bo[buf].modifiable)
        end
      end
    end
    return result
  end)
end

--- Wait for the diff windows to show the expected buffer contents.
--- @param ... string[]
local function expect_diff(...)
  local expected = { ... }
  helpers.expectf(function()
    eq(expected, diff_state(), api.nvim_exec2('messages', { output = true }).output)
  end)
end

--- Read displayed file diffstats in panel order.
--- @return string[]
local function diffstat()
  return exec_lua(function()
    local stats = {}
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(0, -1, 0, -1, { details = true })) do
      local opts = mark[4]
      if opts.virt_text_pos == 'right_align' then
        local text = ''
        for _, chunk in ipairs(opts.virt_text) do
          text = text .. chunk[1]
        end
        stats[#stats + 1] = text
      end
    end
    return stats
  end)
end

--- @param pattern string Lua pattern matching the panel line.
--- @param key? string
local function select_line(pattern, key)
  exec_lua(function(match)
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype == 'gitsigns-diff' then
        vim.api.nvim_set_current_win(win)
        for i, value in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
          if value:match(match) then
            vim.api.nvim_win_set_cursor(win, { i, 0 })
            return
          end
        end
      end
    end
    error('No entry matching: ' .. match)
  end, pattern)
  helpers.feed(key or '<CR>')
end

--- Select a filename at the end of its row, ignoring status and rename origins.
--- @param name string
--- @param key? string
local function select_file(name, key)
  select_line('^%s+.- ' .. vim.pesc(name) .. '$', key)
end

describe('diff panel', function()
  before_each(function()
    helpers.clear()
    helpers.chdir_tmp()
    helpers.setup_gitsigns(helpers.test_config)
    helpers.setup_test_repo({ test_file_text = { 'original' } })
    api.nvim_set_current_dir(helpers.scratch)
  end)

  it('compares explicit revisions with the editable working tree', function()
    helpers.write_to_file(helpers.test_file, { 'committed' })
    git('commit', '-am', 'Change the file')

    helpers.write_to_file(helpers.test_file, { 'working tree' })

    for _, case in ipairs({ { 'HEAD', 'committed' }, { 'HEAD~1', 'original' } }) do
      open_diff_command(case[1] .. ' -- dummy.txt')
      expect_diff({ case[2] }, { 'working tree' })

      select_file('dummy.txt')
      helpers.eq_path(helpers.test_file, api.nvim_buf_get_name(0))
      eq(true, exec_lua('return vim.bo.modifiable'))

      select_file('dummy.txt', 'q')
    end
  end)

  for _, mode in ipairs({ 'worktree', 'commit' }) do
    it('preserves cursors until unloaded: ' .. mode, function()
      api.nvim_command('set nostartofline')
      local lines = { 'one', 'two', 'three', 'four' }
      for _, name in ipairs({ 'a.txt', 'b.txt' }) do
        helpers.write_to_file(helpers.scratch .. '/' .. name, lines)
      end
      git('add', '.')
      git('commit', '-m', 'Add files')

      helpers.write_to_file(helpers.scratch .. '/a.txt', { 'one', 'changed', 'three', 'four' })
      helpers.write_to_file(helpers.scratch .. '/b.txt', { 'changed', 'two', 'three', 'changed' })
      if mode == 'commit' then
        git('commit', '-am', 'Change files')
        open_commit()
      else
        open_diff()
      end

      -- A first visit starts at the hunk, including changes at line one.
      select_file('a.txt')
      local win, buf = api.nvim_get_current_win(), api.nvim_get_current_buf()
      eq({ 2, 0 }, api.nvim_win_get_cursor(win))

      api.nvim_win_set_cursor(win, { 4, 1 })
      select_file('b.txt')
      expect_diff(lines, { 'changed', 'two', 'three', 'changed' })
      eq({ 1, 0 }, api.nvim_win_get_cursor(win)) -- Do not skip a first-line hunk.
      eq(true, api.nvim_buf_is_loaded(buf))

      -- Returning to a loaded buffer preserves the position chosen above.
      select_file('a.txt')
      helpers.expectf(function()
        eq({ 4, 1 }, api.nvim_win_get_cursor(win))
      end)

      -- Explicit unloading makes the next visit start at the hunk again.
      select_file('b.txt')
      expect_diff(lines, { 'changed', 'two', 'three', 'changed' })
      api.nvim_buf_delete(buf, { unload = true })
      select_file('a.txt')
      helpers.expectf(function()
        eq({ 2, 0 }, api.nvim_win_get_cursor(win))
      end)
    end)
  end

  it('does not jump to a hunk for a file loaded before opening the panel', function()
    helpers.write_to_file(helpers.test_file, { 'first', 'middle', 'last' })
    git('commit', '-am', 'Add lines')
    helpers.write_to_file(helpers.test_file, { 'first', 'changed', 'last' })
    helpers.edit(helpers.test_file)
    helpers.wait_for_attach()
    api.nvim_win_set_cursor(0, { 3, 0 })

    open_diff('HEAD')
    select_file('dummy.txt')

    -- The new window starts at line 1; do not jump it to the hunk on line 2.
    eq({ 1, 0 }, api.nvim_win_get_cursor(0))
  end)

  it('filters tracked and untracked paths relative to the current directory', function()
    helpers.write_to_file(helpers.scratch .. '/src/a.lua', { 'before' })
    git('add', '.')
    git('commit', '-m', 'Add files')
    helpers.write_to_file(helpers.scratch .. '/src/a.lua', { 'after' })
    for _, name in ipairs({ 'src/new.lua', 'src/skip.lua', 'src/c.txt', 'outside.lua' }) do
      helpers.write_to_file(helpers.scratch .. '/' .. name, { 'untracked' })
    end
    git('config', 'diff.relative', 'true')
    api.nvim_set_current_dir(helpers.scratch .. '/src')

    open_diff_command('-- *.lua :(exclude)skip.lua')
    eq({ ' src/', '    M a.lua', '   ?? new.lua' }, api.nvim_buf_get_lines(0, 1, -3, false))
    expect_diff({ 'before' }, { 'after' })
    select_file('new.lua')
    expect_diff({ '' }, { 'untracked' })
  end)

  it('preserves spaces, assignments, flags, and numeric path names', function()
    local names = { '--flag', '001', 'a=b', 'nil', 'with space.txt', '{one,two}.txt' }
    for _, name in ipairs(names) do
      helpers.write_to_file(helpers.scratch .. '/' .. name, { name })
    end
    helpers.write_to_file(helpers.scratch .. '/not-selected', { 'outside' })
    open_diff_command('-- --flag 001 a=b nil with\\ space.txt {one,two}.txt')
    eq({
      ' ?? --flag',
      ' ?? 001',
      ' ?? a=b',
      ' ?? nil',
      ' ?? with space.txt',
      ' ?? {one,two}.txt',
    }, api.nvim_buf_get_lines(0, 1, -3, false))
    select_file('with space.txt')
    expect_diff({ '' }, { 'with space.txt' })
  end)

  it('filters ranges by historical paths missing from the working tree', function()
    helpers.write_to_file(helpers.test_file, { 'after' })
    helpers.write_to_file(helpers.scratch .. '/noise.txt', { 'noise' })
    git('add', '.')
    git('commit', '-am', 'Change historical files')
    git('rm', 'dummy.txt')
    git('commit', '-m', 'Remove historical file')

    for _, revision in ipairs({ 'HEAD~2..HEAD~1', 'HEAD~2...HEAD~1' }) do
      for _, separator in ipairs({ ' ', ' -- ' }) do
        open_diff_command(revision .. separator .. 'dummy.txt missing.txt')
        eq({ ' M dummy.txt' }, api.nvim_buf_get_lines(0, 1, -3, false))
        expect_diff({ 'original' }, { 'after' })
        helpers.feed('q')
      end
    end
  end)

  it('accepts Lua pathspecs and shows an empty panel when no paths match', function()
    helpers.write_to_file(helpers.test_file, { 'changed' })
    helpers.write_to_file(helpers.scratch .. '/other.txt', { 'untracked' })
    helpers.edit(helpers.test_file)
    helpers.wait_for_attach()
    helpers.chdir_tmp()
    open_diff(nil, { 'dummy.txt' })
    eq({ '  M dummy.txt' }, api.nvim_buf_get_lines(0, 1, -3, false))
    eq({ { 'original' }, { 'changed' } }, diff_state())
    helpers.feed('q')
    open_diff(nil, { 'missing.txt' })
    eq({ 'No changes' }, api.nvim_buf_get_lines(0, 1, -3, false))
    eq({}, diff_state())
  end)

  it('shows staged, unstaged, and untracked files while excluding ignored files', function()
    git('config', 'status.showUntrackedFiles', 'no')

    -- Establish the tracked paths before mixing index and worktree changes.
    helpers.write_to_file(helpers.scratch .. '/deleted.txt', { 'deleted' })
    helpers.write_to_file(helpers.scratch .. '/old.txt', { 'renamed' })
    helpers.write_to_file(helpers.scratch .. '/recreated.txt', { 'tracked' })
    git('add', '.')
    git('commit', '-m', 'Add files')

    git('rm', 'deleted.txt')
    git('mv', 'old.txt', 'renamed.txt')
    git('rm', '--cached', 'recreated.txt')
    helpers.write_to_file(helpers.scratch .. '/recreated.txt', { 'replacement' })

    helpers.write_to_file(helpers.test_file, { 'staged' })
    helpers.write_to_file(helpers.scratch .. '/staged.txt', { 'added' })
    git('add', 'dummy.txt', 'staged.txt')
    helpers.write_to_file(helpers.test_file, { 'unstaged' })

    helpers.write_to_file(helpers.scratch .. '/new dir/new file.txt', { 'untracked' })
    helpers.write_to_file(helpers.scratch .. '/.git/info/exclude', { 'ignored.txt' })
    helpers.write_to_file(helpers.scratch .. '/ignored.txt', { 'ignored' })

    open_diff('HEAD')
    eq('Diff: HEAD', api.nvim_buf_get_lines(0, 0, 1, false)[1])
    eq({
      ' new dir/',
      '   ?? new file.txt',
      ' D  deleted.txt',
      ' MM dummy.txt',
      ' D? recreated.txt',
      ' R  old.txt -> renamed.txt',
      ' A  staged.txt',
    }, api.nvim_buf_get_lines(0, 1, -3, false))
    eq({ '+1', '-1', '+1 -1', '+1 -1', '+1' }, diffstat())
    eq({ { '' }, { 'untracked' } }, diff_state())

    -- Every status still opens the full comparison against HEAD.
    select_file('dummy.txt')
    expect_diff({ 'original' }, { 'unstaged' })

    select_file('recreated.txt')
    expect_diff({ 'tracked' }, { 'replacement' })

    select_file('renamed.txt')
    expect_diff({ 'renamed' }, { 'renamed' })

    select_file('staged.txt')
    expect_diff({ '' }, { 'added' })

    select_file('new file.txt')
    expect_diff({ '' }, { 'untracked' })
    helpers.eq_path(helpers.scratch .. '/new dir/new file.txt', api.nvim_buf_get_name(0))
    eq(true, exec_lua('return vim.bo.modifiable'))
    helpers.wait_for_attach()
  end)

  it('stages saved changes without changing the diff or unsaved edits', function()
    helpers.write_to_file(helpers.test_file, { 'top', 'original', 'bottom' })
    git('commit', '-am', 'Add lines')

    -- Give the index, disk, and editor buffer distinct contents.
    helpers.write_to_file(helpers.test_file, { 'top', 'staged', 'bottom' })
    git('add', 'dummy.txt')

    local disk = { 'top', 'working', 'bottom' }
    helpers.write_to_file(helpers.test_file, disk)

    helpers.edit(helpers.test_file)
    helpers.wait_for_attach()
    local source = api.nvim_get_current_buf()
    local unsaved = { 'top', 'unsaved', 'bottom' }
    api.nvim_buf_set_lines(source, 0, -1, false, unsaved)

    open_diff()
    local panel, panel_win = api.nvim_get_current_buf(), api.nvim_get_current_win()
    select_file('dummy.txt')
    local right = api.nvim_get_current_win()
    api.nvim_win_set_cursor(right, { 3, 0 })

    exec_lua(function()
      _G.diff_changed_files = {}
      vim.api.nvim_create_autocmd('User', {
        pattern = 'GitSignsChanged',
        callback = function(args)
          table.insert(_G.diff_changed_files, args.data.file)
        end,
      })
    end)

    -- Staging changes the index without reopening the diff or replacing unsaved text.
    for i, action in ipairs({
      { '<Space>', ' M ', disk },
      { 'u', '  M', { 'top', 'original', 'bottom' } },
    }) do
      select_file('dummy.txt', action[1])
      helpers.expectf(function()
        eq({ action[2] .. ' dummy.txt' }, api.nvim_buf_get_lines(panel, 1, -3, false))

        -- The test config disables the watcher: the action must refresh hunks itself.
        eq(
          { '-' .. action[3][2], '+unsaved' },
          exec_lua(function(buf)
            return assert(require('gitsigns').get_hunks(buf))[1].lines
          end, source)
        )
        local changed_files = exec_lua('return _G.diff_changed_files')
        eq(i, #changed_files)
        helpers.eq_path(helpers.test_file, changed_files[i])
      end)

      eq(action[3], git_output('show', ':dummy.txt'))
      eq(panel_win, api.nvim_get_current_win())
      eq({ 3, 0 }, api.nvim_win_get_cursor(right))
      expect_diff({ 'top', 'original', 'bottom' }, unsaved)
    end

    eq(true, api.nvim_get_option_value('modified', { buf = source }))
    eq(disk, helpers.fn.readfile(helpers.test_file))
  end)

  it('stages and unstages listed directory descendants without opening files', function()
    local paths = {
      'src/changed.txt',
      'src/nested/partial.txt',
      'src/excluded.txt',
      'src-other/changed.txt',
    }
    for _, path in ipairs(paths) do
      helpers.write_to_file(helpers.scratch .. '/' .. path, { 'original' })
    end
    git('add', '.')
    git('commit', '-m', 'Add directories')

    -- Mix partial staging with excluded files and a similarly named sibling directory.
    for _, path in ipairs(paths) do
      helpers.write_to_file(helpers.scratch .. '/' .. path, { 'changed' })
    end
    git('add', 'src/nested/partial.txt')
    helpers.write_to_file(helpers.scratch .. '/src/nested/partial.txt', { 'remaining' })
    helpers.write_to_file(helpers.scratch .. '/src/new.txt', { 'new' })

    open_diff(nil, { 'src/', 'src-other/', ':(exclude)src/excluded.txt' })
    local panel, panel_win = api.nvim_get_current_buf(), api.nvim_get_current_win()
    local diff = diff_state()
    select_line('^ src/$')
    local staged = { 'src/changed.txt', 'src/nested/partial.txt', 'src/new.txt' }

    -- Acting on a closed directory must preserve its fold and the displayed file.
    for _, action in ipairs({
      { 's', staged },
      { '<Space>', {} },
    }) do
      select_line('^ src/$', action[1])
      helpers.expectf(function()
        local status = #action[2] > 0 and '     M  ' or '      M '
        eq({ status .. 'partial.txt' }, api.nvim_buf_get_lines(panel, 3, 4, false))
      end)

      eq(action[2], git_output('diff', '--cached', '--name-only'))
      eq(panel_win, api.nvim_get_current_win())
      eq(' src/', api.nvim_get_current_line())
      eq(2, helpers.fn.foldclosed(2))
      eq(diff, diff_state())
      eq(-1, helpers.fn.bufnr(helpers.scratch .. '/src/changed.txt'))
    end
  end)

  it('stages and unstages both sides of a rename using literal paths', function()
    git('config', 'status.renames', 'false')

    -- The destination looks like a pathspec that could also match the unrelated file.
    local name = 'new[1].txt'
    assert((vim.uv or vim.loop).fs_rename(helpers.test_file, helpers.scratch .. '/' .. name))
    git('add', '-N', '--', name)
    helpers.write_to_file(helpers.scratch .. '/new1.txt', { 'unrelated' })

    open_diff()
    local panel = api.nvim_get_current_buf()

    select_file(name, '<Space>')
    helpers.expectf(function()
      eq(
        { ' ?? new1.txt', ' R  dummy.txt -> ' .. name },
        api.nvim_buf_get_lines(panel, 1, -3, false)
      )
    end)
    eq({ 'original' }, git_output('show', ':' .. name))

    select_file(name, '<Space>')
    helpers.expectf(function()
      eq(
        { '  D dummy.txt', ' ?? new1.txt', ' ?? ' .. name },
        api.nvim_buf_get_lines(panel, 1, -3, false)
      )
    end)

    eq({ 'dummy.txt' }, git_output('ls-files'))
    eq({ 'original' }, helpers.fn.readfile(helpers.scratch .. '/' .. name))
    eq({ 'unrelated' }, helpers.fn.readfile(helpers.scratch .. '/new1.txt'))
  end)

  it('shows unresolved merge conflicts with both status columns', function()
    git('checkout', '-b', 'other')
    helpers.write_to_file(helpers.test_file, { 'theirs' })
    git('commit', '-am', 'Other change')

    git('checkout', '-b', 'review', 'HEAD~1')
    helpers.write_to_file(helpers.test_file, { 'ours' })
    git('commit', '-am', 'Our change')
    git('merge', 'other')

    open_diff()
    eq({ ' UU dummy.txt' }, api.nvim_buf_get_lines(0, 1, -3, false))
    expect_diff({ 'ours' }, helpers.fn.readfile(helpers.test_file))
  end)

  it('can stage away changes that cancel out between the index and working tree', function()
    helpers.write_to_file(helpers.test_file, { 'staged' })
    git('add', 'dummy.txt')
    helpers.write_to_file(helpers.test_file, { 'original' })
    open_diff()
    local panel = api.nvim_get_current_buf()
    eq({ ' MM dummy.txt' }, api.nvim_buf_get_lines(panel, 1, -3, false))
    expect_diff({ 'original' }, { 'original' })
    select_file('dummy.txt', '<Space>')
    helpers.expectf(function()
      eq({ 'No changes' }, api.nvim_buf_get_lines(panel, 1, -3, false))
      eq({ { 'original' }, { 'original' } }, diff_state())
    end)
    eq({}, git_output('diff', '--cached'))
  end)

  it('keeps file actions aligned when leaving the tab during a staging refresh', function()
    helpers.write_to_file(helpers.test_file, { 'staged' })
    git('add', 'dummy.txt')
    helpers.write_to_file(helpers.test_file, { 'original' })
    helpers.write_to_file(helpers.scratch .. '/z.txt', { 'untracked' })

    -- Pause after Git is read, before the panel can replace its rows and metadata.
    exec_lua(function()
      local read = require('gitsigns.git.diff')
      local initial = true

      package.loaded['gitsigns.git.diff'] = function(...)
        local base, target, entries, commit = read(...)
        if not initial then
          require('gitsigns.async').await(1, function(resume)
            _G.resume_stage = resume
          end)
        end
        initial = false

        return base, target, entries, commit
      end
    end)

    open_diff()
    local tab = api.nvim_get_current_tabpage()
    select_file('dummy.txt', '<Space>')
    helpers.expectf(function()
      eq(true, exec_lua('return _G.resume_stage ~= nil'))
    end)

    -- The abandoned refresh must leave old rows aligned with their file actions.
    api.nvim_command('tabnew')
    exec_lua('_G.resume_stage()')
    api.nvim_set_current_tabpage(tab)
    select_file('z.txt')
    expect_diff({ '' }, { 'untracked' })
  end)

  it('shows diffstat for renamed, binary, and untracked files', function()
    helpers.write_to_file(helpers.test_file, { 'one', 'two', 'three', 'four', 'five' })
    git('commit', '-am', 'Add lines')
    git('mv', 'dummy.txt', 'renamed file.txt')
    helpers.write_to_file(
      helpers.scratch .. '/renamed file.txt',
      { 'one', 'two', 'three', 'four', 'new' }
    )
    helpers.write_to_file(helpers.scratch .. '/binary', { 'a\0b' })
    git('add', '.')
    git('commit', '-m', 'Rename and add binary')
    open_commit('HEAD')
    eq({ 'Bin', '+1 -1' }, diffstat())
    helpers.feed('q')

    helpers.write_to_file(helpers.scratch .. '/binary', { 'c\0d' })
    helpers.write_to_file(helpers.scratch .. '/new-binary', { 'a\0b' })
    helpers.write_to_file(helpers.scratch .. '/-', { 'first', 'second' })
    helpers.write_to_file(helpers.scratch .. '/empty', {})
    open_diff()
    eq({ '+2', 'Bin', 'Bin' }, diffstat())
  end)

  it('highlights only the selected file changes when switching working buffers', function()
    for _, file in ipairs({ 'a', 'b' }) do
      helpers.write_to_file(
        helpers.scratch .. '/' .. file .. '.txt',
        { file, 'before', file .. ' end' }
      )
    end
    git('add', '.')
    git('commit', '-m', 'Add two files')
    for _, file in ipairs({ 'a', 'b' }) do
      helpers.write_to_file(
        helpers.scratch .. '/' .. file .. '.txt',
        { file, 'after', file .. ' end' }
      )
    end
    open_diff()

    for _, file in ipairs({ 'a', 'b', 'a' }) do
      select_file(file .. '.txt')
      helpers.expectf(function()
        eq({ { file, 'before', file .. ' end' }, { file, 'after', file .. ' end' } }, diff_state())
        eq(
          { { false, true, false }, { false, true, false } },
          exec_lua(function()
            local result = {}
            for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
              if vim.wo[win].diff then
                result[#result + 1] = vim.api.nvim_win_call(win, function()
                  return vim.tbl_map(function(lnum)
                    return vim.fn.diff_hlID(lnum, 1) ~= 0
                  end, { 1, 2, 3 })
                end)
              end
            end
            return result
          end)
        )
      end)
    end
  end)

  it('preserves working buffers and restores their mappings when the panel closes', function()
    helpers.write_to_file(helpers.test_file, { 'disk' })
    helpers.write_to_file(helpers.scratch .. '/z.txt', { 'untracked' })
    helpers.edit(helpers.scratch .. '/z.txt')
    helpers.wait_for_attach()
    local untracked = api.nvim_get_current_buf()
    local untracked_maps = api.nvim_buf_get_keymap(untracked, 'n')
    helpers.edit(helpers.test_file)
    helpers.wait_for_attach()
    local source = api.nvim_get_current_buf()
    api.nvim_buf_set_lines(source, 0, -1, false, { 'unsaved' })
    exec_lua(function()
      vim.keymap.set('n', ']f', function()
        _G.original_mapping = true
      end, { buffer = true, desc = 'Original mapping' })
    end)
    open_diff()
    eq({ { 'original' }, { 'unsaved' } }, diff_state())
    select_file('dummy.txt')
    helpers.expectf(function()
      eq(source, api.nvim_get_current_buf())
    end)
    helpers.feed(']f')
    expect_diff({ '' }, { 'untracked' })
    eq(untracked, api.nvim_get_current_buf())
    api.nvim_buf_set_lines(untracked, 0, -1, false, { 'edited' })
    helpers.feed('[f')
    expect_diff({ 'original' }, { 'unsaved' })
    select_file('dummy.txt', 'q')
    eq(source, api.nvim_get_current_buf())
    eq({ 'unsaved' }, api.nvim_buf_get_lines(source, 0, -1, false))
    eq({ 'edited' }, api.nvim_buf_get_lines(untracked, 0, -1, false))
    eq(true, exec_lua('return vim.bo.modified'))
    eq(false, exec_lua('return vim.wo.diff'))
    eq('Original mapping', exec_lua("return vim.fn.maparg(']f', 'n', false, true).desc"))
    eq(untracked_maps, api.nvim_buf_get_keymap(untracked, 'n'))
    helpers.feed(']f')
    eq(true, exec_lua('return _G.original_mapping'))
  end)

  it('decodes revision contents like working files', function()
    exec_lua("vim.o.fileencodings = 'ucs-bom,utf-8,latin1'")
    helpers.write_to_file(helpers.test_file, { 'caf\233', 'before', 'end' })
    git('add', '.')
    git('commit', '-m', 'Add Latin-1 text')
    helpers.write_to_file(helpers.test_file, { 'caf\233', 'after', 'end' })

    for _, revision in ipairs({ false, 'HEAD~1' }) do
      if revision then
        git('add', '.')
        git('commit', '-m', 'Change Latin-1 text')
        git('rm', 'dummy.txt')
        git('commit', '-m', 'Remove from the working tree')
      end
      if revision then
        open_commit(revision)
      else
        open_diff()
      end
      eq({ { 'café', 'before', 'end' }, { 'café', 'after', 'end' } }, diff_state())
      helpers.feed('q')
    end
  end)

  it('preserves mappings outside the diff windows while a panel is open', function()
    helpers.write_to_file(helpers.test_file, { 'changed' })
    helpers.write_to_file(helpers.scratch .. '/z.txt', { 'untracked' })
    helpers.edit(helpers.test_file)
    helpers.wait_for_attach()
    local source_win = api.nvim_get_current_win()
    exec_lua(function()
      _G.mapping_calls = {}
      _G.RecordMapping = function(kind)
        table.insert(_G.mapping_calls, { kind, vim.v.count1, vim.v.register })
      end
      vim.keymap.set('n', ']f', function()
        _G.RecordMapping('local')
      end, { buffer = true })
      vim.keymap.set('n', '[f', 'RecordMapping()', { expr = true, remap = true })
      vim.cmd([[
        function! RecordMapping()
          call v:lua.RecordMapping('global')
          return 'gZ'
        endfunction
        nnoremap gZ <Cmd>let g:remapped = v:count1<CR>
      ]])
    end)
    open_diff()
    local panel_win = api.nvim_get_current_win()
    select_file('dummy.txt')
    local diff_win = api.nvim_get_current_win()

    api.nvim_set_current_win(source_win)
    helpers.feed('"a3]f"b2[f')
    eq({ { 'local', 3, 'a' }, { 'global', 2, 'b' } }, exec_lua('return _G.mapping_calls'))
    eq(2, exec_lua('return vim.g.remapped'))

    api.nvim_set_current_win(diff_win)
    api.nvim_command('split')
    helpers.feed('4]f')
    eq({ 'local', 4, '"' }, exec_lua('return _G.mapping_calls[3]'))
    api.nvim_command('close')
    helpers.feed(']f')
    expect_diff({ '' }, { 'untracked' })
    helpers.feed('[f')
    expect_diff({ 'original' }, { 'changed' })
    eq(3, exec_lua('return #_G.mapping_calls'))
    api.nvim_set_current_win(panel_win)
    helpers.feed('q')
    helpers.feed(']f')
    eq({ 'local', 1, '"' }, exec_lua('return _G.mapping_calls[4]'))
  end)

  it('shows staged and untracked files before the first commit', function()
    helpers.chdir_tmp()
    helpers.setup_test_repo({ no_add = true, test_file_text = { 'staged' } })
    git('add', 'dummy.txt')
    helpers.write_to_file(helpers.test_file, { 'working tree' })
    helpers.write_to_file(helpers.scratch .. '/new.txt', { 'untracked' })
    api.nvim_set_current_dir(helpers.scratch)
    open_diff()
    local panel = api.nvim_get_current_buf()
    eq({ ' AM dummy.txt', ' ?? new.txt' }, api.nvim_buf_get_lines(0, 1, -3, false))
    eq({ '+1', '+1' }, diffstat())
    eq({ { '' }, { 'working tree' } }, diff_state())
    select_file('new.txt')
    expect_diff({ '' }, { 'untracked' })
    for _, action in ipairs({
      { 's', ' A ', { 'dummy.txt', 'new.txt' } },
      { 'u', ' ??', { 'dummy.txt' } },
    }) do
      select_file('new.txt', action[1])
      helpers.expectf(function()
        eq({ action[2] .. ' new.txt' }, api.nvim_buf_get_lines(panel, 2, 3, false))
      end)
      eq(action[3], git_output('ls-files'))
    end
  end)

  it('shows and refreshes an untracked repository as a gitlink', function()
    helpers.mkdir(helpers.scratch .. '/nested')
    git('-C', 'nested', 'init', '-q')
    git('-C', 'nested', 'config', 'user.name', 'Test')
    git('-C', 'nested', 'config', 'user.email', 'test@example.com')
    helpers.write_to_file(helpers.scratch .. '/nested/file.txt', { 'nested' })
    git('-C', 'nested', 'add', '.')
    git('-C', 'nested', 'commit', '-qm', 'Nested commit')
    local oid = assert(git_output('-C', 'nested', 'rev-parse', 'HEAD')[1])

    open_diff()
    eq({ ' ?? nested' }, api.nvim_buf_get_lines(0, 1, -3, false))
    eq({ '+1' }, diffstat())
    eq({ { '' }, { 'Subproject commit ' .. oid } }, diff_state())

    select_file('nested')
    helpers.expectf(function()
      eq(true, exec_lua('return vim.wo.diff'))
    end)
    local buf = api.nvim_get_current_buf()

    -- Reopening the gitlink reads its current HEAD into the retained buffer.
    git('-C', 'nested', 'commit', '--allow-empty', '-qm', 'Next nested commit')
    oid = assert(git_output('-C', 'nested', 'rev-parse', 'HEAD')[1])
    select_file('nested')
    expect_diff({ '' }, { 'Subproject commit ' .. oid })
    eq(buf, api.nvim_get_current_buf())
  end)

  it('compares the targets of working-tree symlinks', function()
    if helpers.fn.has('win32') == 1 then
      helpers.pending('requires symlink support')
    end
    local uv = vim.uv or vim.loop
    local path = helpers.scratch .. '/link'
    assert(uv.fs_symlink('dummy.txt', path))
    git('add', 'link')
    git('commit', '-m', 'Add a symlink')
    assert(uv.fs_unlink(path))
    assert(uv.fs_symlink('missing.txt', path))
    assert(uv.fs_symlink('dummy.txt', helpers.scratch .. '/new-link'))
    open_diff()
    local panel = api.nvim_get_current_buf()
    eq({ '  M link', ' ?? new-link' }, api.nvim_buf_get_lines(0, 1, -3, false))
    eq({ '+1 -1', '+1' }, diffstat())
    eq({ { 'dummy.txt' }, { 'missing.txt' } }, diff_state())

    select_file('link')
    local buf = api.nvim_get_current_buf()
    select_file('new-link')
    expect_diff({ '' }, { 'dummy.txt' })

    -- A staging refresh must not leave the old symlink target cached on revisit.
    assert(uv.fs_unlink(path))
    assert(uv.fs_symlink('latest.txt', path))
    select_file('link', 's')
    helpers.expectf(function()
      eq({ ' M  link' }, api.nvim_buf_get_lines(panel, 1, 2, false))
    end)

    select_file('link')
    expect_diff({ 'dummy.txt' }, { 'latest.txt' })
    eq(buf, api.nvim_get_current_buf())
  end)

  it('reuses the startup window for a root commit and closes cleanly', function()
    local source_win = api.nvim_get_current_win()
    local source_tab = api.nvim_get_current_tabpage()
    open_commit()
    eq({ source_tab }, api.nvim_list_tabpages())
    eq(3, #api.nvim_tabpage_list_wins(0))
    eq(true, exec_lua('return vim.wo[...].diff', source_win))
    eq({ { '' }, { 'original' } }, diff_state())
    local bufs =
      exec_lua('return vim.tbl_map(vim.api.nvim_win_get_buf, vim.api.nvim_tabpage_list_wins(0))')
    helpers.feed('q')
    eq(1, #api.nvim_list_tabpages())
    eq('', api.nvim_buf_get_name(0))
    eq({ '' }, api.nvim_buf_get_lines(0, 0, -1, false))
    eq(false, exec_lua('return vim.wo.winfixbuf'))
    eq(1, #api.nvim_tabpage_list_wins(0))
    helpers.expectf(function()
      for _, buf in ipairs(bufs) do
        eq(false, api.nvim_buf_is_valid(buf))
      end
    end)
  end)

  it('reuses the startup window beneath floating UI', function()
    for _, focusable in ipairs({ true, false }) do
      local source_win = api.nvim_get_current_win()
      local source_tab = api.nvim_get_current_tabpage()
      local float = exec_lua(function(focus)
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'Startup UI' })
        vim.bo[buf].bufhidden = 'wipe'
        return vim.api.nvim_open_win(buf, false, {
          relative = 'editor',
          row = 0,
          col = 0,
          width = 20,
          height = 1,
          focusable = focus,
        })
      end, focusable)
      open_commit('HEAD')
      eq({ source_tab }, api.nvim_list_tabpages())
      eq(true, exec_lua('return vim.wo[...].diff', source_win))
      eq(true, api.nvim_win_is_valid(float))
      eq({ 'Startup UI' }, api.nvim_buf_get_lines(api.nvim_win_get_buf(float), 0, -1, false))
      helpers.feed('q')
    end
  end)

  it('preserves an unnamed draft in its own tab', function()
    local source = api.nvim_get_current_buf()
    local source_win = api.nvim_get_current_win()
    api.nvim_buf_set_lines(source, 0, -1, false, { 'unsaved draft' })
    open_commit('HEAD')
    eq(2, #api.nvim_list_tabpages())
    eq(source, api.nvim_win_get_buf(source_win))
    eq({ 'unsaved draft' }, api.nvim_buf_get_lines(source, 0, -1, false))
    helpers.feed('q')
    eq(source_win, api.nvim_get_current_win())
    eq(true, exec_lua('return vim.bo.modified'))
  end)

  it('preserves existing splits when the current buffer is unnamed', function()
    api.nvim_command('vsplit')
    local source_tab = api.nvim_get_current_tabpage()
    local wins = api.nvim_tabpage_list_wins(source_tab)
    open_commit('HEAD')
    eq(2, #api.nvim_list_tabpages())
    eq(wins, api.nvim_tabpage_list_wins(source_tab))
    helpers.feed('q')
    eq(source_tab, api.nvim_get_current_tabpage())
    eq(wins, api.nvim_tabpage_list_wins(0))
  end)

  it('switches between added, deleted, and renamed historical files', function()
    helpers.write_to_file(helpers.scratch .. '/deleted.txt', { 'deleted' })
    git('add', '.')
    git('commit', '-m', 'Add a file to delete')
    git('mv', helpers.test_file, 'renamed.txt')
    git('rm', 'deleted.txt')
    helpers.write_to_file(helpers.scratch .. '/added.txt', { 'added' })
    git('add', '.')
    git('commit', '-m', 'Rename, add and delete')
    git('rm', 'renamed.txt', 'added.txt')
    git('commit', '-m', 'Remove historical paths from the checkout')

    open_commit('HEAD~1')
    local wins = api.nvim_tabpage_list_wins(0)
    eq({ { '' }, { 'added' } }, diff_state())
    select_file('deleted.txt')
    expect_diff({ 'deleted' }, { '' })
    select_file('renamed.txt')
    expect_diff({ 'original' }, { 'original' })
    eq(wins, api.nvim_tabpage_list_wins(0))

    select_file('renamed.txt', 'O')
    helpers.expectf(function()
      eq(2, #api.nvim_list_tabpages())
    end)
    eq({ 'original' }, api.nvim_buf_get_lines(0, 0, -1, false))
    eq(true, api.nvim_buf_get_name(0):match(':dummy.txt$') ~= nil)
  end)

  it('preserves unsaved work and uses the attached repository outside cwd', function()
    helpers.write_to_file(helpers.test_file, { 'committed' })
    git('add', '.')
    git('commit', '-m', 'Change the file')
    helpers.edit(helpers.test_file)
    helpers.wait_for_attach()
    local source = api.nvim_get_current_buf()
    api.nvim_buf_set_lines(source, 0, -1, false, { 'unsaved' })
    helpers.chdir_tmp()
    api.nvim_command('Gitsigns show_commit HEAD')
    expect_diff({ 'original' }, { 'committed' })
    helpers.feed('q')
    eq(source, api.nvim_get_current_buf())
    eq({ 'unsaved' }, api.nvim_buf_get_lines(source, 0, -1, false))
    eq(true, exec_lua('return vim.bo.modified'))
    eq(false, exec_lua('return vim.wo.diff'))
  end)

  it('wraps the summary above a nonselectable separator', function()
    local summary = 'Keep the commit summary readable when the file panel is narrow'
    git('commit', '--allow-empty', '-m', summary)
    open_commit()
    local panel = api.nvim_get_current_win()
    for _, case in ipairs({ { 36, 2 }, { 20, 4 } }) do
      api.nvim_win_set_width(panel, case[1])
      helpers.expectf(function()
        eq(case[2], api.nvim_win_text_height(panel, { start_row = 1, end_row = 1 }).all)
        eq(1, api.nvim_win_text_height(panel, { start_row = 2, end_row = 2 }).fill)
      end)
    end
    helpers.feed('2j')
    eq({ 3, 0 }, api.nvim_win_get_cursor(panel))
    select_line('^' .. vim.pesc(summary) .. '$')
    helpers.expectf(function()
      eq('gitcommit', exec_lua('return vim.bo.filetype'))
    end)
  end)

  it('switches between the commit message and file diffs beside the panel', function()
    helpers.write_to_file(helpers.test_file, { 'committed' })
    local body = { 'Explain the change', '', 'Why this change is needed:', '' }
    for i = 1, 40 do
      body[#body + 1] = 'Detail ' .. i
    end
    git(
      '-c',
      'user.name=Panel Author',
      '-c',
      'user.email=author@example.com',
      'commit',
      '--date=2001-02-03T04:05:06+0130',
      '-am',
      table.concat(body, '\n')
    )
    local sha =
      vim.trim(helpers.fn.system({ 'git', '-C', helpers.scratch, 'rev-parse', '--short', 'HEAD' }))
    local header = sha .. ' Explain the change'

    open_commit('HEAD')
    eq(
      false,
      exec_lua(function()
        local ok = pcall(vim.cmd.enew)
        return ok
      end)
    )
    eq({ sha, 'Explain the change' }, api.nvim_buf_get_lines(0, 0, 2, false))
    eq({ { 'original' }, { 'committed' } }, diff_state())

    local panel = api.nvim_get_current_win()
    local tab = api.nvim_get_current_tabpage()
    local message = vim.list_extend({
      header,
      'Author: Panel Author <author@example.com>',
      'Date:   2001-02-03T04:05:06+01:30',
      '',
    }, body)

    -- Moving the ref must not change which commit the open panel describes.
    git('commit', '--allow-empty', '-m', 'A later commit')
    local message_buf --- @type integer?
    for _, close in ipairs({ false, 'q', ':close<CR>' }) do
      select_line('^' .. vim.pesc(sha) .. '$')
      local win = api.nvim_get_current_win()
      local buf = api.nvim_get_current_buf()
      message_buf = message_buf or buf

      eq(message_buf, buf)
      eq(1, #api.nvim_list_tabpages())
      eq(tab, api.nvim_get_current_tabpage())
      eq(2, #api.nvim_tabpage_list_wins(0))
      eq(true, api.nvim_win_get_position(panel)[2] < api.nvim_win_get_position(win)[2])
      eq('', api.nvim_win_get_config(win).relative)
      eq(true, exec_lua('return vim.bo.buflisted'))
      eq('gitcommit', exec_lua('return vim.bo.filetype'))
      eq(false, exec_lua('return vim.bo.modifiable'))
      eq(message, api.nvim_buf_get_lines(0, 0, -1, false))
      eq({}, diff_state())

      -- Closing the message pane must still allow its buffer to be reused.
      helpers.feed('G')
      eq('Detail 40', api.nvim_get_current_line())
      if close then
        helpers.feed(close)
        eq(false, api.nvim_win_is_valid(win))
        eq(panel, api.nvim_get_current_win())
        eq({ panel }, api.nvim_tabpage_list_wins(0))
      end

      eq({ 1, 0 }, api.nvim_win_get_cursor(panel))
      select_file('dummy.txt')
      expect_diff({ 'original' }, { 'committed' })
      eq(true, api.nvim_buf_is_loaded(buf))
      eq(1, #api.nvim_list_tabpages())
      eq(3, #api.nvim_tabpage_list_wins(0))
    end

    -- The retained message is released when the whole review closes.
    select_file('dummy.txt', 'q')
    helpers.expectf(function()
      eq(false, api.nvim_buf_is_valid(message_buf))
    end)
  end)

  it('keeps full commit navigation separate from the panel message', function()
    helpers.setup_gitsigns(vim.tbl_extend('force', helpers.test_config, { _commit_maps = true }))
    helpers.write_to_file(helpers.test_file, { 'changed' })
    git('commit', '-am', 'Change the file')
    local sha = vim.trim(helpers.fn.system({ 'git', '-C', helpers.scratch, 'rev-parse', 'HEAD' }))
    helpers.edit(helpers.test_file)
    helpers.wait_for_attach()
    local source = api.nvim_get_current_win()
    api.nvim_command('Gitsigns show_commit ' .. sha .. ' vsplit')
    helpers.expectf(function()
      eq('commit ' .. sha, api.nvim_buf_get_lines(0, 0, 1, false)[1])
    end)
    local full_win = api.nvim_get_current_win()
    local full_buf = api.nvim_get_current_buf()
    local full_text = api.nvim_buf_get_lines(full_buf, 0, -1, false)
    eq('git', exec_lua('return vim.bo.filetype'))
    eq(true, vim.tbl_contains(full_text, '+changed'))
    local parent = full_text[3]:match('parent (%x+)')

    api.nvim_set_current_win(source)
    open_commit(sha)
    local header = api.nvim_buf_get_lines(0, 0, 1, false)[1]
    select_line('^' .. vim.pesc(header) .. '$')
    local message_buf = api.nvim_get_current_buf()
    local message_text = api.nvim_buf_get_lines(message_buf, 0, -1, false)
    eq(false, message_buf == full_buf)
    eq('gitcommit', exec_lua('return vim.bo.filetype'))
    eq(false, vim.tbl_contains(message_text, '+changed'))

    api.nvim_set_current_win(full_win)
    helpers.feed('3G<CR>')
    helpers.expectf(function()
      eq('commit ' .. parent, api.nvim_buf_get_lines(0, 0, 1, false)[1])
    end)
    helpers.feed('<C-o>')
    helpers.expectf(function()
      eq(full_text, api.nvim_buf_get_lines(0, 0, -1, false))
    end)
    api.nvim_win_set_cursor(0, { helpers.fn.index(full_text, '+changed') + 1, 0 })
    helpers.feed('<CR>')
    helpers.expectf(function()
      eq({ 'changed' }, api.nvim_buf_get_lines(0, 0, -1, false))
    end)
    helpers.wait_for_attach(api.nvim_get_current_buf())
    eq(message_text, api.nvim_buf_get_lines(message_buf, 0, -1, false))
  end)

  it('shows the message of a commit with no changed files', function()
    git('commit', '--allow-empty', '-m', 'An empty commit')
    open_commit('HEAD')
    eq({ 1, 0 }, api.nvim_win_get_cursor(0))
    eq('No changes', api.nvim_buf_get_lines(0, 2, -3, false)[1])
    eq({}, diff_state())
    helpers.feed('<CR>')
    eq('An empty commit', api.nvim_buf_get_lines(0, 4, 5, false)[1])
    helpers.feed('q')
    eq('gitsigns-diff', exec_lua('return vim.bo.filetype'))
    helpers.feed('q')
    eq(1, #api.nvim_list_tabpages())
  end)

  it('shows available keys and returns from help without changing the view', function()
    open_commit('HEAD')
    local panel = api.nvim_get_current_win()
    local panel_buf = api.nvim_get_current_buf()
    local cursor = api.nvim_win_get_cursor(panel)
    local wins = api.nvim_tabpage_list_wins(0)
    eq(true, api.nvim_buf_get_lines(panel_buf, -2, -1, false)[1]:find('g? help', 1, true) ~= nil)

    for _, close in ipairs({ '<Esc>', 'q', 'g?' }) do
      helpers.feed('g?')
      helpers.expectf(function()
        eq(
          false,
          panel == api.nvim_get_current_win(),
          api.nvim_exec2('messages', { output = true }).output
        )
      end)
      local help = api.nvim_get_current_win()
      eq(false, panel == help)
      eq(false, api.nvim_win_get_config(help).relative == '')
      local lines = api.nvim_buf_get_lines(0, 0, -1, false)
      local text = table.concat(lines, '\n')
      for _, map in ipairs(api.nvim_buf_get_keymap(panel_buf, 'n')) do
        eq(true, text:find(map.lhs .. ' ', 1, true) ~= nil, 'Missing help for ' .. map.lhs)
      end
      for _, key in ipairs({ ']f / [f', ']c / [c' }) do
        eq(true, text:find(key, 1, true) ~= nil, 'Missing help for ' .. key)
      end
      eq(true, text:find('show commit message', 1, true) ~= nil)
      eq(#lines, api.nvim_win_get_height(help))
      helpers.feed(close)
      eq(false, api.nvim_win_is_valid(help))
      eq(panel, api.nvim_get_current_win())
      eq(cursor, api.nvim_win_get_cursor(panel))
      eq(wins, api.nvim_tabpage_list_wins(0))
      eq({ { '' }, { 'original' } }, diff_state())
    end
  end)

  it('opens a clicked file from another window', function()
    local screen = require('nvim-test.screen').new(110, 24)
    screen:attach()
    finally(function()
      screen:detach()
    end)

    exec_lua("vim.o.mouse = 'a'; vim.o.mousetime = 0")
    helpers.write_to_file(helpers.test_file, { 'changed' })
    helpers.write_to_file(helpers.scratch .. '/z.txt', { 'new' })

    open_diff()
    local panel = api.nvim_get_current_win()
    select_file('dummy.txt')

    -- Click the panel while a diff window has focus, including both mouse events.
    api.nvim_command('redraw')
    local pos = helpers.fn.screenpos(panel, 3, 1)
    api.nvim_input_mouse('left', 'press', '', 0, pos.row - 1, pos.col - 1)
    api.nvim_input_mouse('left', 'release', '', 0, pos.row - 1, pos.col - 1)

    expect_diff({ '' }, { 'new' })
    eq(true, exec_lua('return vim.wo.diff'))
  end)

  it('opens a diff with Shift-Enter without moving the panel cursor', function()
    helpers.write_to_file(helpers.test_file, { 'committed' })
    helpers.write_to_file(helpers.scratch .. '/z.txt', { 'z' })
    git('add', '.')
    git('commit', '-m', 'Change two files')
    open_commit('HEAD')
    eq({ { 'original' }, { 'committed' } }, diff_state())
    select_file('z.txt', '$')
    local panel = api.nvim_get_current_win()
    local cursor = api.nvim_win_get_cursor(panel)
    helpers.feed('<S-CR>')
    expect_diff({ '' }, { 'z' })
    eq(panel, api.nvim_get_current_win())
    eq(cursor, api.nvim_win_get_cursor(panel))

    helpers.feed('<CR>')
    helpers.expectf(function()
      eq(true, exec_lua('return vim.wo.diff'))
    end)
    eq(false, panel == api.nvim_get_current_win())
  end)

  it('navigates files from either diff buffer and reveals folded entries', function()
    helpers.write_to_file(helpers.scratch .. '/src/a.txt', { 'a' })
    helpers.write_to_file(helpers.scratch .. '/src/nested/b.txt', { 'b' })
    helpers.write_to_file(helpers.scratch .. '/z.txt', { 'z' })
    git('add', '.')
    git('commit', '-m', 'Add nested files')
    open_commit('HEAD')
    local panel = api.nvim_get_current_win()
    --- Read highlighted filename text, independently of the cursor.
    --- @return string[]
    local function selected()
      return exec_lua(function(win)
        local buf = vim.api.nvim_win_get_buf(win)
        local lines = {}
        for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })) do
          if mark[4].hl_group == 'QuickFixLine' then
            local line = vim.api.nvim_buf_get_lines(buf, mark[2], mark[2] + 1, false)[1]
            lines[#lines + 1] = line:sub(mark[3] + 1, mark[4].end_col)
          end
        end
        return lines
      end, panel)
    end
    eq({ 'b.txt' }, selected())
    select_line('^ src/$', 'zM')
    select_line('^ src/$')
    select_file('a.txt')
    helpers.expectf(function()
      eq(true, exec_lua('return vim.wo.diff'))
    end)
    local right = api.nvim_get_current_win()
    local left = helpers.fn.win_getid(helpers.fn.winnr('h'))
    -- Browsing the panel must not change where navigation starts in the diff.
    select_file('z.txt', '0')
    eq({ 'a.txt' }, selected())
    api.nvim_set_current_win(right)
    helpers.feed('[f')
    expect_diff({ '' }, { 'b' })
    eq({ 'b.txt' }, selected())
    eq(right, api.nvim_get_current_win())
    eq({ 5, 0 }, api.nvim_win_get_cursor(panel))
    eq(
      -1,
      exec_lua(function(win)
        return vim.api.nvim_win_call(win, function()
          return vim.fn.foldclosed(5)
        end)
      end, panel)
    )

    api.nvim_set_current_win(left)
    helpers.feed('2]f')
    expect_diff({ '' }, { 'z' })
    eq({ 'z.txt' }, selected())
    eq(left, api.nvim_get_current_win())
    helpers.feed(']f')
    eq({ { '' }, { 'z' } }, diff_state())
    helpers.feed('2[f')
    expect_diff({ '' }, { 'b' })
    eq({ 'b.txt' }, selected())
    eq(left, api.nvim_get_current_win())
    helpers.feed('[f')
    eq({ { '' }, { 'b' } }, diff_state())
    select_file('z.txt', '<S-CR>')
    expect_diff({ '' }, { 'z' })
    eq({ 'z.txt' }, selected())
    helpers.feed('gg<CR>')
    eq({}, selected())
  end)

  it('uses the current panel when revision buffers are shared between tabs', function()
    helpers.write_to_file(helpers.scratch .. '/a.txt', { 'a' })
    helpers.write_to_file(helpers.scratch .. '/b.txt', { 'b' })
    git('add', '.')
    git('commit', '-m', 'Add two files')
    helpers.edit(helpers.test_file)
    helpers.wait_for_attach()
    local source_tab = api.nvim_get_current_tabpage()
    open_commit('HEAD')
    local first_tab = api.nvim_get_current_tabpage()
    select_file('a.txt')
    helpers.expectf(function()
      eq(true, exec_lua('return vim.wo.diff'))
    end)
    local first_win = api.nvim_get_current_win()
    local shared_buf = api.nvim_get_current_buf()

    api.nvim_set_current_tabpage(source_tab)
    open_commit('HEAD')
    local second_tab = api.nvim_get_current_tabpage()
    select_file('a.txt')
    helpers.expectf(function()
      eq(true, exec_lua('return vim.wo.diff'))
    end)
    local second_win = api.nvim_get_current_win()
    eq(shared_buf, api.nvim_get_current_buf())

    api.nvim_set_current_win(first_win)
    helpers.feed(']f')
    expect_diff({ '' }, { 'b' })
    eq(first_tab, api.nvim_get_current_tabpage())
    eq(shared_buf, api.nvim_win_get_buf(second_win))

    api.nvim_set_current_win(second_win)
    helpers.feed(']f')
    expect_diff({ '' }, { 'b' })
    eq(second_tab, api.nvim_get_current_tabpage())
    select_file('b.txt', 'q')
    api.nvim_set_current_win(first_win)
    helpers.feed('[f')
    expect_diff({ '' }, { 'a' })
    eq(first_win, api.nvim_get_current_win())
  end)

  it('lists directories first and folds nested and leading-space names with icons', function()
    exec_lua(function()
      package.preload['nvim-web-devicons'] = function()
        return {
          get_icon = function(name)
            assert(not name:find('/'), 'Expected a filename, not a path')
            return '', 'DevIconDefault'
          end,
        }
      end
    end)
    helpers.write_to_file(helpers.scratch .. '/  src/  a.txt', { 'a' })
    helpers.write_to_file(helpers.scratch .. '/  src/ nested/  b.txt', { 'b' })
    helpers.write_to_file(helpers.scratch .. '/  src/z.txt', { 'z' })
    helpers.write_to_file(helpers.scratch .. '/tests/t.txt', { 'test' })
    helpers.write_to_file(helpers.scratch .. '/aaa.txt', { 'root' })
    helpers.write_to_file(helpers.scratch .. '/top.txt', { 'top' })
    git('add', '.')
    git('commit', '-m', 'Add nested files')
    open_commit('HEAD')
    eq({
      ' \\  src/',
      '   \\ nested/',
      '     A   b.txt',
      '   A   a.txt',
      '   A z.txt',
      ' tests/',
      '   A t.txt',
      ' A aaa.txt',
      ' A top.txt',
    }, api.nvim_buf_get_lines(0, 2, -3, false))
    eq(
      { DevIconDefault = 6, Directory = 3 },
      exec_lua(function()
        local counts = {}
        for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(0, -1, 0, -1, { details = true })) do
          local opts = mark[4]
          if opts.virt_text_pos == 'inline' then
            local icon, hl = unpack(opts.virt_text[1])
            assert(icon == (hl == 'Directory' and ' ' or ' '))
            counts[hl] = (counts[hl] or 0) + 1
          end
        end
        return counts
      end)
    )
    eq({ { '' }, { 'b' } }, diff_state())
    eq(-1, exec_lua('return vim.fn.foldclosed(3)'))

    select_line('^   \\ nested/$')
    eq({ 4, 5 }, exec_lua('return { vim.fn.foldclosed(5), vim.fn.foldclosedend(4) }'))
    select_line('^ \\  src/$')
    eq(7, exec_lua('return vim.fn.foldclosedend(3)'))
    eq(-1, exec_lua('return vim.fn.foldclosed(8)'))
    eq({ { '' }, { 'b' } }, diff_state())

    select_file('top.txt')
    expect_diff({ '' }, { 'top' })
    select_line('^ \\  src/$')
    eq(4, exec_lua('return vim.fn.foldclosed(4)'))
    select_line('^   \\ nested/$')
    select_file('  b.txt')
    expect_diff({ '' }, { 'b' })

    select_line('^ \\  src/$', 'zM')
    eq(
      { 7, 9, -1 },
      exec_lua('return { vim.fn.foldclosedend(3), vim.fn.foldclosedend(8), vim.fn.foldclosed(10) }')
    )
    helpers.feed('zR')
    eq(-1, exec_lua('return vim.fn.foldclosed(6)'))
  end)

  it('groups a rename under its destination and opens its original path', function()
    helpers.mkdir(helpers.scratch .. '/old')
    git('mv', helpers.test_file, 'old/original.txt')
    git('commit', '-m', 'Move into a directory')
    helpers.mkdir(helpers.scratch .. '/new')
    git('mv', 'old/original.txt', 'new/renamed.txt')
    git('commit', '-m', 'Rename across directories')
    open_commit('HEAD')
    eq({ ' new/', '   R old/original.txt -> renamed.txt' }, api.nvim_buf_get_lines(0, 2, -3, false))
    select_file('renamed.txt', 'O')
    helpers.expectf(function()
      eq(2, #api.nvim_list_tabpages())
    end)
    eq({ 'original' }, api.nvim_buf_get_lines(0, 0, -1, false))
    eq(true, api.nvim_buf_get_name(0):match(':old/original.txt$') ~= nil)
  end)

  it('opens commit diffs and full commits from the blame panel', function()
    helpers.edit(helpers.test_file)
    helpers.wait_for_attach()
    helpers.chdir_tmp()
    exec_lua(function()
      require('gitsigns.async').run(require('gitsigns.actions.blame').blame):wait(5000)
    end)
    local blame = api.nvim_get_current_win()
    helpers.feed('D')
    helpers.expectf(function()
      eq('gitsigns-diff', exec_lua('return vim.bo.filetype'))
      eq({ { '' }, { 'original' } }, diff_state())
    end)
    helpers.feed('q')
    api.nvim_set_current_win(blame)
    helpers.feed('e')
    helpers.expectf(function()
      eq('git', exec_lua('return vim.bo.filetype'))
      eq(true, vim.tbl_contains(api.nvim_buf_get_lines(0, 0, -1, false), '+original'))
    end)
  end)

  it('cleans up when the panel closes during a file read', function()
    helpers.write_to_file(helpers.scratch .. '/a.txt', { 'a' })
    helpers.write_to_file(helpers.scratch .. '/b.txt', { 'b' })
    git('add', '.')
    git('commit', '-m', 'Add two files')
    open_commit('HEAD')
    exec_lua(function()
      local Repo = require('gitsigns.git.repo')
      local read = Repo.get_show_text
      Repo.get_show_text = function(self, object, encoding)
        Repo.get_show_text = read
        require('gitsigns.async').await(1, function(resume)
          _G.resume_read = resume
        end)
        return read(self, object, encoding)
      end
    end)
    select_file('b.txt')
    helpers.expectf(function()
      eq(true, exec_lua('return _G.resume_read ~= nil'))
    end)
    select_file('b.txt', 'q')
    eq(1, #api.nvim_list_tabpages())
    exec_lua('_G.resume_read()')
    helpers.expectf(function()
      eq(
        false,
        exec_lua(function()
          for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_get_name(buf):match('^gitsigns') then
              return true
            end
          end
          return false
        end)
      )
    end)
    eq(1, #api.nvim_list_tabpages())
  end)

  it('distinguishes endpoint comparisons from merge-base comparisons', function()
    git('checkout', '-b', 'topic')
    helpers.write_to_file(helpers.test_file, { 'topic' })
    git('add', '.')
    git('commit', '-m', 'Topic change')
    git('checkout', 'main')
    helpers.write_to_file(helpers.test_file, { 'main' })
    git('add', '.')
    git('commit', '-m', 'Main change')
    open_diff('main..topic')
    eq({ { 'main' }, { 'topic' } }, diff_state())
    helpers.feed('q')
    open_diff('main...topic')
    eq({ { 'original' }, { 'topic' } }, diff_state())
  end)

  it('handles clean worktrees, empty ranges, and invalid revisions', function()
    open_diff()
    eq('Diff: working tree', api.nvim_buf_get_lines(0, 0, 1, false)[1])
    eq('No changes', api.nvim_get_current_line())
    eq({}, diff_state())
    helpers.feed('gg<CR>')
    eq('gitsigns-diff', exec_lua('return vim.bo.filetype'))
    helpers.feed('q')
    open_diff('HEAD..HEAD')
    eq('Diff: HEAD..HEAD', api.nvim_buf_get_lines(0, 0, 1, false)[1])
    eq('No changes', api.nvim_get_current_line())
    eq({}, diff_state())
    helpers.feed('gg<CR>')
    eq('gitsigns-diff', exec_lua('return vim.bo.filetype'))
    helpers.feed('q')
    eq(1, #api.nvim_list_tabpages())
    exec_lua(function()
      require('gitsigns.async').run(require('gitsigns.actions.diff'), 'does-not-exist'):wait(5000)
    end)
    eq(1, #api.nvim_list_tabpages())
    eq(
      true,
      api.nvim_exec2('messages', { output = true }).output:find('Needed a single revision', 1, true)
        ~= nil
    )
  end)
end)
