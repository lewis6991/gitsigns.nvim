local helpers = require('test.gs_helpers')
local api = helpers.api
local eq = helpers.eq
local exec_lua = helpers.exec_lua

helpers.env()

describe('revision buffers', function()
  before_each(function()
    helpers.clear()
    helpers.chdir_tmp()
    helpers.setup_gitsigns(helpers.test_config)
    helpers.setup_test_repo()
  end)

  it('can be hidden after the source window closes', function()
    helpers.edit(helpers.test_file)
    helpers.wait_for_attach()
    local source = api.nvim_get_current_win()
    exec_lua(function()
      require('gitsigns.async')
        .run(require('gitsigns.actions.diffthis').diffthis, 'HEAD', {})
        :wait(1000)
    end)
    eq(2, #api.nvim_list_wins())
    api.nvim_win_close(source, false)
    local revision = api.nvim_get_current_buf()
    eq(true, api.nvim_buf_get_name(revision):find('^gitsigns://') ~= nil)
    -- Keep the revision loaded when leaving its window.
    api.nvim_set_option_value('bufhidden', 'hide', { buf = revision })
    api.nvim_command('enew')
    eq(-1, helpers.fn.bufwinid(revision))
  end)

  it('shows the current file at a revision and writes its index view', function()
    local file = helpers.scratch .. '/nested/file with spaces.txt'
    helpers.mkdir(helpers.scratch .. '/nested')
    helpers.write_to_file(file, { 'committed' })
    helpers.git('add', '.')
    helpers.git('commit', '-m', 'Add a nested file')
    helpers.write_to_file(file, { 'index' })
    helpers.git('add', '.')
    helpers.write_to_file(file, { 'working tree' })
    helpers.edit(file)
    helpers.wait_for_attach()
    helpers.chdir_tmp()

    api.nvim_command('Gitsigns show HEAD:%')
    helpers.expectf(function()
      eq({ 'committed' }, api.nvim_buf_get_lines(0, 0, -1, false))
      eq(false, exec_lua('return vim.bo.modifiable'))
    end)
    eq(1, #api.nvim_tabpage_list_wins(0))
    helpers.wait_for_attach()

    api.nvim_command('Gitsigns show :%')
    helpers.expectf(function()
      eq('acwrite', exec_lua('return vim.bo.buftype'))
      eq({ 'index' }, api.nvim_buf_get_lines(0, 0, -1, false))
    end)
    helpers.wait_for_attach()
    api.nvim_buf_set_lines(0, 0, -1, false, { 'staged' })
    api.nvim_command('write')
    helpers.expectf(function()
      eq(
        { 'staged' },
        helpers.fn.systemlist({
          'git',
          '-C',
          helpers.scratch,
          'show',
          ':nested/file with spaces.txt',
        })
      )
    end)
    eq({ 'working tree' }, helpers.fn.readfile(file))
  end)

  it('shows another file at the same revision with its own line endings', function()
    helpers.git('config', 'core.autocrlf', 'false')
    helpers.write_to_file(
      helpers.scratch .. '/other file=.txt',
      { 'other', 'file' },
      { newline = '\r\n' }
    )
    helpers.git('add', 'other file=.txt')
    helpers.git('commit', '-m', 'Add another file')
    helpers.setup_gitsigns(vim.tbl_extend('force', helpers.test_config, { base = 'HEAD' }))
    helpers.edit(helpers.test_file)
    helpers.wait_for_attach()
    eq('unix', exec_lua('return vim.bo.fileformat'))

    api.nvim_command('Gitsigns show HEAD:other\\ file=.txt --open=split')
    helpers.expectf(function()
      eq({ 'other', 'file' }, api.nvim_buf_get_lines(0, 0, -1, false))
    end)
    eq(2, #api.nvim_tabpage_list_wins(0))
    eq('dos', exec_lua('return vim.bo.fileformat'))
    helpers.wait_for_attach()

    api.nvim_command('Gitsigns show :dummy.txt')
    helpers.expectf(function()
      eq('acwrite', exec_lua('return vim.bo.buftype'))
    end)
    helpers.wait_for_attach()
    api.nvim_buf_set_lines(0, 0, -1, false, { 'staged' })
    api.nvim_command('write')
    helpers.expectf(function()
      eq(
        { 'staged' },
        helpers.fn.systemlist({ 'git', '-C', helpers.scratch, 'show', ':dummy.txt' })
      )
    end)
    eq({ 'other', 'file' }, helpers.fn.readfile(helpers.scratch .. '/other file=.txt'))
    eq(
      { 'dummy.txt' },
      helpers.fn.systemlist({ 'git', '-C', helpers.scratch, 'diff', '--cached', '--name-only' })
    )
  end)

  it('reads a deleted historical file without an attached source buffer', function()
    exec_lua("vim.o.fileencodings = 'ucs-bom,utf-8,latin1'")
    helpers.git('config', 'core.autocrlf', 'false')
    helpers.write_to_file(helpers.scratch .. '/old.txt', { 'caf\233', 'old' }, { newline = '\r\n' })
    helpers.git('add', 'old.txt')
    helpers.git('commit', '-m', 'Add historical file')
    helpers.git('rm', 'old.txt')
    helpers.git('commit', '-m', 'Delete historical file')

    exec_lua(function(root)
      require('gitsigns.async')
        .run(function()
          local repo = assert(require('gitsigns.git.repo').get(root))
          local _, buf =
            require('gitsigns.actions.diffthis').create_revision_buf(repo, 'HEAD~1', 'old.txt')
          vim.api.nvim_set_current_buf(assert(buf))
          repo:unref()
        end)
        :wait(5000)
    end, helpers.scratch)
    eq({ 'café', 'old' }, api.nvim_buf_get_lines(0, 0, -1, false))
    eq('dos', exec_lua('return vim.bo.fileformat'))
    eq('latin1', exec_lua('return vim.bo.fileencoding'))
    eq(false, exec_lua('return vim.bo.modifiable'))
    helpers.wait_for_attach()
  end)
end)
