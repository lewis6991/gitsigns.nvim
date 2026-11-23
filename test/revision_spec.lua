local helpers = require('test.gs_helpers')
local api = helpers.api
local eq = helpers.eq
local exec_lua = helpers.exec_lua

helpers.env()

--- Read the fixture file's index bytes without converting line endings.
--- @return string
local function index_text()
  return exec_lua(function(root)
    local result = vim.system({ 'git', '-C', root, 'show', ':dummy.txt' }, { text = false }):wait()
    assert(result.code == 0, result.stderr)
    return result.stdout
  end, helpers.scratch)
end

--- Open checkout-filtered text as Fugitive does, then detect its line endings.
--- @param revision string
local function edit_fugitive(revision)
  exec_lua(function(root, rev)
    local result = vim
      .system({ 'git', '-C', root, 'cat-file', '--filters', rev .. ':dummy.txt' }, { text = false })
      :wait()
    assert(result.code == 0, result.stderr)

    local path = vim.fn.tempname()
    local file = assert(io.open(path, 'wb'))
    file:write(result.stdout)
    file:close()
    vim.cmd('noautocmd edit ' .. vim.fn.fnameescape(path))
    vim.fn.delete(path)

    vim.bo.buftype = 'nowrite'
    local name = ('fugitive://%s/.git//%s/dummy.txt'):format(root, rev:gsub('^:', ''))
    vim.api.nvim_buf_set_name(0, name)
    vim.cmd('Gitsigns attach')
  end, helpers.scratch, revision)
  helpers.wait_for_attach()
end

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

  it('keeps the encoding and BOM when writing the index', function()
    exec_lua('vim.g.editorconfig = false')
    local encoded = exec_lua(function()
      return assert(
        vim.iconv('\239\187\191Кирилл\nВторая строка\n', 'utf-8', 'utf-16le')
      )
    end)
    helpers.write_to_file(helpers.test_file, { encoded }, { trailing_newline = false })
    helpers.git('commit', '-am', 'Add UTF-16 text with a BOM')
    helpers.edit(helpers.test_file)
    helpers.wait_for_attach()
    local source = api.nvim_get_current_buf()

    api.nvim_command('Gitsigns show :%')
    helpers.expectf(function()
      eq('acwrite', exec_lua('return vim.bo.buftype'))
      eq({ 'Кирилл', 'Вторая строка' }, api.nvim_buf_get_lines(0, 0, -1, false))
    end)
    helpers.wait_for_attach()

    api.nvim_buf_set_lines(0, 1, 2, false, { 'Изменено' })
    api.nvim_command('write')
    local expected = exec_lua(function()
      return assert(vim.iconv('\239\187\191Кирилл\nИзменено\n', 'utf-8', 'utf-16le'))
    end)
    helpers.expectf(function()
      eq(expected, index_text())
      eq(false, exec_lua('return vim.bo.modified'))
    end)
    api.nvim_set_current_buf(source)
    helpers.check({ signs = { changed = 1 } })
  end)

  it('keeps literal CR in Unix index buffers', function()
    exec_lua('vim.g.editorconfig = false')
    helpers.write_to_file(helpers.scratch .. '/.gitattributes', { '*.txt text' })
    helpers.write_to_file(helpers.test_file, { 'one', 'keep\r', 'three' }, { newline = '\r\n' })
    helpers.git('add', '.')
    helpers.git('commit', '-m', 'Add literal CR')

    -- The worktree uses LF, but the stored index still contains a literal CR.
    helpers.write_to_file(helpers.test_file, { 'one', 'keep', 'three' })
    helpers.edit(helpers.test_file)
    helpers.wait_for_attach()
    api.nvim_command('Gitsigns show :%')
    helpers.expectf(function()
      eq('acwrite', exec_lua('return vim.bo.buftype'))
    end)
    helpers.wait_for_attach()
    eq('unix', exec_lua('return vim.bo.fileformat'))
    eq({ 'one', 'keep\r', 'three' }, api.nvim_buf_get_lines(0, 0, -1, false))
    eq({}, exec_lua('return require("gitsigns").get_hunks()'))

    -- Writing the unchanged view must not run CRLF conversion a second time.
    api.nvim_command('setlocal modified | write')
    helpers.expectf(function()
      eq(false, exec_lua('return vim.bo.modified'))
      eq('one\nkeep\r\nthree\n', index_text())
    end)

    edit_fugitive(':0')
    eq('unix', exec_lua('return vim.bo.fileformat'))
    eq({ 'one', 'keep\r', 'three' }, api.nvim_buf_get_lines(0, 0, -1, false))
    eq({}, exec_lua('return require("gitsigns").get_hunks()'))

    -- Staging another line must not clean the literal CR in the stored text.
    api.nvim_command('cd ' .. helpers.fn.fnameescape(helpers.scratch))
    api.nvim_buf_set_lines(0, 2, 3, false, { 'staged' })
    helpers.expectf(function()
      eq(1, #exec_lua('return require("gitsigns").get_hunks()'))
    end)
    helpers.stage_hunk({ 3, 3 })
    eq('one\nkeep\r\nstaged\n', index_text())
  end)

  it('writes explicit index line-ending changes when conversion is disabled', function()
    exec_lua('vim.g.editorconfig = false')
    helpers.git('config', 'core.autocrlf', 'false')
    helpers.write_to_file(helpers.test_file, { 'one', 'two', 'three' })
    helpers.git('commit', '-am', 'Store LF')
    helpers.edit(helpers.test_file)
    helpers.wait_for_attach()
    api.nvim_command('Gitsigns show :%')
    helpers.expectf(function()
      eq('acwrite', exec_lua('return vim.bo.buftype'))
    end)
    helpers.wait_for_attach()

    api.nvim_command('setlocal fileformat=dos | write')
    helpers.expectf(function()
      eq(false, exec_lua('return vim.bo.modified'))
      eq('one\r\ntwo\r\nthree\r\n', index_text())
    end)
  end)

  it('resets and partially stages a Fugitive DOS buffer', function()
    exec_lua('vim.g.editorconfig = false')
    helpers.git('config', 'core.autocrlf', 'true')
    helpers.write_to_file(helpers.test_file, { 'one', 'two', 'three' })
    helpers.git('commit', '-am', 'Store LF')

    edit_fugitive(':0')
    eq('dos', exec_lua('return vim.bo.fileformat'))
    eq({ 'one', 'two', 'three' }, api.nvim_buf_get_lines(0, 0, -1, false))
    eq({}, exec_lua('return require("gitsigns").get_hunks()'))

    api.nvim_buf_set_lines(0, 1, 2, false, { 'edited' })
    helpers.expectf(function()
      eq(1, #exec_lua('return require("gitsigns").get_hunks()'))
    end)
    api.nvim_command('Gitsigns reset_buffer')
    helpers.expectf(function()
      eq({ 'one', 'two', 'three' }, api.nvim_buf_get_lines(0, 0, -1, false))
      eq({}, exec_lua('return require("gitsigns").get_hunks()'))
    end)

    -- Staging filtered text must still store LF in the index.
    api.nvim_command('cd ' .. helpers.fn.fnameescape(helpers.scratch))
    api.nvim_buf_set_lines(0, 0, 0, false, { 'unstaged' })
    api.nvim_buf_set_lines(0, 2, 3, false, { 'from Fugitive' })
    helpers.expectf(function()
      eq(2, #exec_lua('return require("gitsigns").get_hunks()'))
    end)
    helpers.stage_hunk({ 3, 3 })
    eq('one\nfrom Fugitive\nthree\n', index_text())

    helpers.command_wait_gitsigns_update('Gitsigns undo_stage_hunk')
    eq('one\ntwo\nthree\n', index_text())
  end)

  it('stages a literal CR in a Fugitive buffer only once', function()
    exec_lua('vim.g.editorconfig = false')
    helpers.git('config', 'core.autocrlf', 'true')
    helpers.write_to_file(helpers.scratch .. '/.gitattributes', { '*.txt text' })
    helpers.write_to_file(helpers.test_file, { 'one' })
    helpers.git('commit', '-am', 'Store LF')

    edit_fugitive(':0')
    api.nvim_command('cd ' .. helpers.fn.fnameescape(helpers.scratch))
    eq('dos', exec_lua('return vim.bo.fileformat'))
    api.nvim_buf_set_lines(0, 0, -1, false, { 'one\r' })
    helpers.expectf(function()
      eq(1, #exec_lua('return require("gitsigns").get_hunks()'))
    end)

    api.nvim_command('Gitsigns stage_buffer')
    helpers.expectf(function()
      eq('one\r\n', index_text())
      eq({}, exec_lua('return require("gitsigns").get_hunks()'))
    end)
  end)

  it('stages explicit Fugitive line-ending changes without conversion', function()
    exec_lua('vim.g.editorconfig = false')
    helpers.git('config', 'core.autocrlf', 'false')
    helpers.write_to_file(helpers.scratch .. '/.gitattributes', { '*.txt -text' })
    helpers.write_to_file(helpers.test_file, { 'one', 'two' })
    helpers.git('commit', '-am', 'Store LF')

    edit_fugitive(':0')
    api.nvim_command('cd ' .. helpers.fn.fnameescape(helpers.scratch))
    eq('unix', exec_lua('return vim.bo.fileformat'))
    api.nvim_command('setlocal fileformat=dos')
    helpers.command_wait_gitsigns_update('doautocmd OptionSet fileformat')
    eq(1, #exec_lua('return require("gitsigns").get_hunks()'))

    api.nvim_command('Gitsigns stage_buffer')
    helpers.expectf(function()
      eq('one\r\ntwo\r\n', index_text())
      eq({}, exec_lua('return require("gitsigns").get_hunks()'))
    end)
  end)

  it('keeps historical CRLF text after the worktree is normalized', function()
    exec_lua('vim.g.editorconfig = false')
    helpers.git('config', 'core.autocrlf', 'false')
    helpers.write_to_file(helpers.test_file, { 'one', 'two', 'three' }, { newline = '\r\n' })
    helpers.git('commit', '-am', 'Store CRLF')

    helpers.git('config', 'core.autocrlf', 'input')
    helpers.git('add', '--renormalize', '.')
    helpers.git('commit', '-m', 'Normalize line endings')
    helpers.write_to_file(helpers.test_file, { 'one', 'two', 'three' })
    helpers.edit(helpers.test_file)
    helpers.wait_for_attach()
    eq({}, exec_lua('return require("gitsigns").get_hunks()'))

    api.nvim_command('Gitsigns show HEAD~1:%')
    helpers.expectf(function()
      eq(false, exec_lua('return vim.bo.modifiable'))
    end)
    helpers.wait_for_attach()
    eq({ 'one\r', 'two\r', 'three\r' }, api.nvim_buf_get_lines(0, 0, -1, false))
    eq({}, exec_lua('return require("gitsigns").get_hunks()'))
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
