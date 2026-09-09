local helpers = require('test.gs_helpers')
local api = helpers.api
local eq = helpers.eq
local exec_lua = helpers.exec_lua
local git = helpers.git

helpers.env()

--- @param revision? string
--- @param paths? string[]
local function open_diff(revision, paths)
  exec_lua(function(opts)
    local done = false
    --- @param err? string
    local function callback(err)
      assert(not err, err)
      done = true
    end
    if opts.paths then
      require('gitsigns').diff(opts.revision, opts.paths, callback)
    else
      require('gitsigns').diff(opts.revision, callback)
    end
    assert(vim.wait(5000, function()
      return done
    end))
  end, { revision = revision, paths = paths })
  eq(
    'gitsigns-diff',
    exec_lua('return vim.bo.filetype'),
    api.nvim_exec2('messages', { output = true }).output
  )
end

--- Open a diff through the user command and wait for its panel.
--- @param args string
local function open_diff_command(args)
  api.nvim_command('Gitsigns diff ' .. args)
  helpers.expectf(function()
    eq('gitsigns-diff', exec_lua('return vim.bo.filetype'))
  end)
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
    eq(expected, diff_state())
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

--- @param line string
--- @param key? string
local function select_file(line, key)
  exec_lua(function(text)
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype == 'gitsigns-diff' then
        vim.api.nvim_set_current_win(win)
        for i, value in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
          if value == text then
            vim.api.nvim_win_set_cursor(win, { i, 0 })
            return
          end
        end
      end
    end
    error('No entry: ' .. text)
  end, line)
  helpers.feed(key or '<CR>')
end

describe('diff panel', function()
  before_each(function()
    helpers.clear()
    helpers.chdir_tmp()
    helpers.setup_gitsigns(helpers.test_config)
    helpers.setup_test_repo({ test_file_text = { 'original' } })
    api.nvim_set_current_dir(helpers.scratch)
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
    eq({ ' src/', '   M a.lua', '   ? new.lua' }, api.nvim_buf_get_lines(0, 3, -1, false))
    expect_diff({ 'before' }, { 'after' })
    select_file('   ? new.lua')
    expect_diff({ '' }, { 'untracked' })
  end)

  it('preserves spaces, assignments, flags, and numeric path names', function()
    local names = { '--flag', '001', 'a=b', 'nil', 'with space.txt', '{one,two}.txt' }
    for _, name in ipairs(names) do
      helpers.write_to_file(helpers.scratch .. '/' .. name, { name })
    end
    helpers.write_to_file(helpers.scratch .. '/not-selected', { 'outside' })
    open_diff_command('-- --flag 001 a=b nil with\\ space.txt {one,two}.txt')
    eq(
      { ' ? --flag', ' ? 001', ' ? a=b', ' ? nil', ' ? with space.txt', ' ? {one,two}.txt' },
      api.nvim_buf_get_lines(0, 3, -1, false)
    )
    select_file(' ? with space.txt')
    expect_diff({ '' }, { 'with space.txt' })
  end)

  it('filters commits and ranges by historical paths missing from the working tree', function()
    helpers.write_to_file(helpers.test_file, { 'after' })
    helpers.write_to_file(helpers.scratch .. '/noise.txt', { 'noise' })
    git('add', '.')
    git('commit', '-am', 'Change historical files')
    git('rm', 'dummy.txt')
    git('commit', '-m', 'Remove historical file')

    for _, revision in ipairs({ 'HEAD~1', 'HEAD~2..HEAD~1', 'HEAD~2...HEAD~1' }) do
      for _, separator in ipairs({ ' ', ' -- ' }) do
        open_diff_command(revision .. separator .. 'dummy.txt missing.txt')
        eq({ ' M dummy.txt' }, api.nvim_buf_get_lines(0, 3, -1, false))
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
    eq({ ' M dummy.txt' }, api.nvim_buf_get_lines(0, 3, -1, false))
    eq({ { 'original' }, { 'changed' } }, diff_state())
    helpers.feed('q')
    open_diff(nil, { 'missing.txt' })
    eq({ 'No changes' }, api.nvim_buf_get_lines(0, 3, -1, false))
    eq({}, diff_state())
  end)

  it('shows staged, unstaged, and untracked files while excluding ignored files', function()
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

    open_diff()
    eq('Diff: working tree', api.nvim_buf_get_lines(0, 0, 1, false)[1])
    eq({
      ' D deleted.txt',
      ' M dummy.txt',
      ' new dir/',
      '   ? new file.txt',
      ' M recreated.txt',
      ' R old.txt -> renamed.txt',
      ' A staged.txt',
    }, api.nvim_buf_get_lines(0, 3, -1, false))
    eq({ '-1', '+1 -1', '+1', '+1 -1', '+1' }, diffstat())
    eq({ { 'deleted' }, { '' } }, diff_state())
    select_file(' M dummy.txt')
    expect_diff({ 'original' }, { 'unstaged' })
    select_file(' M recreated.txt')
    expect_diff({ 'tracked' }, { 'replacement' })
    select_file(' R old.txt -> renamed.txt')
    expect_diff({ 'renamed' }, { 'renamed' })
    select_file(' A staged.txt')
    expect_diff({ '' }, { 'added' })
    select_file('   ? new file.txt')
    expect_diff({ '' }, { 'untracked' })
    helpers.eq_path(helpers.scratch .. '/new dir/new file.txt', api.nvim_buf_get_name(0))
    eq(true, exec_lua('return vim.bo.modifiable'))
    helpers.wait_for_attach()
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
    open_diff('HEAD')
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
      select_file(' M ' .. file .. '.txt')
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
    select_file(' M dummy.txt')
    helpers.expectf(function()
      eq(source, api.nvim_get_current_buf())
    end)
    helpers.feed(']f')
    expect_diff({ '' }, { 'untracked' })
    eq(untracked, api.nvim_get_current_buf())
    api.nvim_buf_set_lines(untracked, 0, -1, false, { 'edited' })
    helpers.feed('[f')
    expect_diff({ 'original' }, { 'unsaved' })
    select_file(' M dummy.txt', 'q')
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
      open_diff(revision or nil)
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
    select_file(' M dummy.txt')
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
    eq({ ' A dummy.txt', ' ? new.txt' }, api.nvim_buf_get_lines(0, 3, -1, false))
    eq({ '+1', '+1' }, diffstat())
    eq({ { '' }, { 'working tree' } }, diff_state())
    select_file(' ? new.txt')
    expect_diff({ '' }, { 'untracked' })
  end)

  it('shows an untracked repository as a gitlink', function()
    helpers.mkdir(helpers.scratch .. '/nested')
    git('-C', 'nested', 'init', '-q')
    helpers.write_to_file(helpers.scratch .. '/nested/file.txt', { 'nested' })
    git('-C', 'nested', 'add', '.')
    git(
      '-C',
      'nested',
      '-c',
      'user.name=Test',
      '-c',
      'user.email=test@example.com',
      'commit',
      '-qm',
      'Nested commit'
    )
    local oid = vim.trim(
      helpers.fn.system({ 'git', '-C', helpers.scratch .. '/nested', 'rev-parse', 'HEAD' })
    )
    open_diff()
    eq({ ' ? nested' }, api.nvim_buf_get_lines(0, 3, -1, false))
    eq({ '+1' }, diffstat())
    eq({ { '' }, { 'Subproject commit ' .. oid } }, diff_state())
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
    eq({ ' M link', ' ? new-link' }, api.nvim_buf_get_lines(0, 3, -1, false))
    eq({ '+1 -1', '+1' }, diffstat())
    eq({ { 'dummy.txt' }, { 'missing.txt' } }, diff_state())
    select_file(' ? new-link')
    expect_diff({ '' }, { 'dummy.txt' })
  end)

  it('reuses the startup window for a root commit and closes cleanly', function()
    local source_win = api.nvim_get_current_win()
    local source_tab = api.nvim_get_current_tabpage()
    open_diff('HEAD')
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
      open_diff('HEAD')
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
    open_diff('HEAD')
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
    open_diff('HEAD')
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

    open_diff('HEAD~1')
    local wins = api.nvim_tabpage_list_wins(0)
    eq({ { '' }, { 'added' } }, diff_state())
    select_file(' D deleted.txt')
    expect_diff({ 'deleted' }, { '' })
    select_file(' R dummy.txt -> renamed.txt')
    expect_diff({ 'original' }, { 'original' })
    eq(wins, api.nvim_tabpage_list_wins(0))

    select_file(' R dummy.txt -> renamed.txt', 'O')
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
    open_diff('HEAD')
    eq({ { 'original' }, { 'committed' } }, diff_state())
    helpers.feed('q')
    eq(source, api.nvim_get_current_buf())
    eq({ 'unsaved' }, api.nvim_buf_get_lines(source, 0, -1, false))
    eq(true, exec_lua('return vim.bo.modified'))
    eq(false, exec_lua('return vim.wo.diff'))
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
    open_diff('HEAD')
    eq(
      false,
      exec_lua(function()
        local ok = pcall(vim.cmd.enew)
        return ok
      end)
    )
    eq(header, api.nvim_buf_get_lines(0, 0, 1, false)[1])
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
    for _, close in ipairs({ false, 'q', ':close<CR>' }) do
      select_file(header)
      local win = api.nvim_get_current_win()
      local buf = api.nvim_get_current_buf()
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
      helpers.feed('G')
      eq('Detail 40', api.nvim_get_current_line())
      if close then
        helpers.feed(close)
        eq(false, api.nvim_win_is_valid(win))
        eq(panel, api.nvim_get_current_win())
        eq({ panel }, api.nvim_tabpage_list_wins(0))
      end
      eq({ 1, 0 }, api.nvim_win_get_cursor(panel))
      select_file(' M dummy.txt')
      expect_diff({ 'original' }, { 'committed' })
      eq(false, api.nvim_buf_is_valid(buf))
      eq(1, #api.nvim_list_tabpages())
      eq(3, #api.nvim_tabpage_list_wins(0))
    end
  end)

  it('keeps full commit navigation separate from the panel message', function()
    helpers.setup_gitsigns(vim.tbl_extend('force', helpers.test_config, { _commit_maps = true }))
    helpers.write_to_file(helpers.test_file, { 'changed' })
    git('commit', '-am', 'Change the file')
    local sha = vim.trim(helpers.fn.system({ 'git', '-C', helpers.scratch, 'rev-parse', 'HEAD' }))
    helpers.edit(helpers.test_file)
    helpers.wait_for_attach()
    local source = api.nvim_get_current_win()
    api.nvim_command('Gitsigns show_commit ' .. sha)
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
    open_diff(sha)
    local header = api.nvim_buf_get_lines(0, 0, 1, false)[1]
    select_file(header)
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
    open_diff('HEAD')
    eq({ 1, 0 }, api.nvim_win_get_cursor(0))
    eq('No changes', api.nvim_buf_get_lines(0, 3, -1, false)[1])
    eq({}, diff_state())
    helpers.feed('<CR>')
    eq('An empty commit', api.nvim_buf_get_lines(0, 4, 5, false)[1])
    helpers.feed('q')
    eq('gitsigns-diff', exec_lua('return vim.bo.filetype'))
    helpers.feed('q')
    eq(1, #api.nvim_list_tabpages())
  end)

  it('shows available keys and returns from help without changing the view', function()
    open_diff('HEAD')
    local panel = api.nvim_get_current_win()
    local panel_buf = api.nvim_get_current_buf()
    local cursor = api.nvim_win_get_cursor(panel)
    local wins = api.nvim_tabpage_list_wins(0)
    eq(true, api.nvim_buf_get_lines(panel_buf, 1, 2, false)[1]:find('g? help', 1, true) ~= nil)

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

  it('opens a diff with Shift-Enter without moving the panel cursor', function()
    helpers.write_to_file(helpers.test_file, { 'committed' })
    helpers.write_to_file(helpers.scratch .. '/z.txt', { 'z' })
    git('add', '.')
    git('commit', '-m', 'Change two files')
    open_diff('HEAD')
    eq({ { 'original' }, { 'committed' } }, diff_state())
    select_file(' A z.txt', '$')
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
    open_diff('HEAD')
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
    eq({ 'a.txt' }, selected())
    select_file(' src/', 'zM')
    select_file(' src/')
    select_file('   A a.txt')
    helpers.expectf(function()
      eq(true, exec_lua('return vim.wo.diff'))
    end)
    local right = api.nvim_get_current_win()
    local left = helpers.fn.win_getid(helpers.fn.winnr('h'))
    -- Browsing the panel must not change where navigation starts in the diff.
    select_file(' A z.txt', '0')
    eq({ 'a.txt' }, selected())
    api.nvim_set_current_win(right)
    helpers.feed(']f')
    expect_diff({ '' }, { 'b' })
    eq({ 'b.txt' }, selected())
    eq(right, api.nvim_get_current_win())
    eq({ 7, 0 }, api.nvim_win_get_cursor(panel))
    eq(
      -1,
      exec_lua(function(win)
        return vim.api.nvim_win_call(win, function()
          return vim.fn.foldclosed(7)
        end)
      end, panel)
    )

    api.nvim_set_current_win(left)
    helpers.feed(']f')
    expect_diff({ '' }, { 'z' })
    eq({ 'z.txt' }, selected())
    eq(left, api.nvim_get_current_win())
    helpers.feed(']f')
    eq({ { '' }, { 'z' } }, diff_state())
    helpers.feed('2[f')
    expect_diff({ '' }, { 'a' })
    eq({ 'a.txt' }, selected())
    eq(left, api.nvim_get_current_win())
    helpers.feed('[f')
    eq({ { '' }, { 'a' } }, diff_state())
    select_file(' A z.txt', '<S-CR>')
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
    open_diff('HEAD')
    local first_tab = api.nvim_get_current_tabpage()
    select_file(' A a.txt')
    helpers.expectf(function()
      eq(true, exec_lua('return vim.wo.diff'))
    end)
    local first_win = api.nvim_get_current_win()
    local shared_buf = api.nvim_get_current_buf()

    api.nvim_set_current_tabpage(source_tab)
    open_diff('HEAD')
    local second_tab = api.nvim_get_current_tabpage()
    select_file(' A a.txt')
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
    select_file(' A b.txt', 'q')
    api.nvim_set_current_win(first_win)
    helpers.feed('[f')
    expect_diff({ '' }, { 'a' })
    eq(first_win, api.nvim_get_current_win())
  end)

  it('folds nested directories and leading-space names with icons', function()
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
    helpers.write_to_file(helpers.scratch .. '/top.txt', { 'top' })
    git('add', '.')
    git('commit', '-m', 'Add nested files')
    open_diff('HEAD')
    eq({
      ' \\  src/',
      '   A   a.txt',
      '   \\ nested/',
      '     A   b.txt',
      '   A z.txt',
      ' tests/',
      '   A t.txt',
      ' A top.txt',
    }, api.nvim_buf_get_lines(0, 3, -1, false))
    eq(
      { DevIconDefault = 5, Directory = 3 },
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
    eq({ { '' }, { 'a' } }, diff_state())
    eq(-1, exec_lua('return vim.fn.foldclosed(4)'))

    select_file('   \\ nested/')
    eq({ 6, 7 }, exec_lua('return { vim.fn.foldclosed(7), vim.fn.foldclosedend(6) }'))
    select_file(' \\  src/')
    eq(8, exec_lua('return vim.fn.foldclosedend(4)'))
    eq(-1, exec_lua('return vim.fn.foldclosed(9)'))
    eq({ { '' }, { 'a' } }, diff_state())

    select_file(' A top.txt')
    expect_diff({ '' }, { 'top' })
    select_file(' \\  src/')
    eq(6, exec_lua('return vim.fn.foldclosed(6)'))
    select_file('   \\ nested/')
    select_file('     A   b.txt')
    expect_diff({ '' }, { 'b' })

    select_file(' \\  src/', 'zM')
    eq(
      { 8, 10, -1 },
      exec_lua('return { vim.fn.foldclosedend(4), vim.fn.foldclosedend(9), vim.fn.foldclosed(11) }')
    )
    helpers.feed('zR')
    eq(-1, exec_lua('return vim.fn.foldclosed(7)'))
  end)

  it('groups a rename under its destination and opens its original path', function()
    helpers.mkdir(helpers.scratch .. '/old')
    git('mv', helpers.test_file, 'old/original.txt')
    git('commit', '-m', 'Move into a directory')
    helpers.mkdir(helpers.scratch .. '/new')
    git('mv', 'old/original.txt', 'new/renamed.txt')
    git('commit', '-m', 'Rename across directories')
    open_diff('HEAD')
    eq({ ' new/', '   R old/original.txt -> renamed.txt' }, api.nvim_buf_get_lines(0, 3, -1, false))
    select_file('   R old/original.txt -> renamed.txt', 'O')
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
    open_diff('HEAD')
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
    select_file(' A b.txt')
    helpers.expectf(function()
      eq(true, exec_lua('return _G.resume_read ~= nil'))
    end)
    select_file(' A b.txt', 'q')
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
