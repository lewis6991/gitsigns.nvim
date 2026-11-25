local helpers = require('test.gs_helpers')

local clear = helpers.clear
local cleanup = helpers.cleanup
local command = helpers.api.nvim_command
local eq = helpers.eq
local exec_lua = helpers.exec_lua
local git = helpers.git
local setup_gitsigns = helpers.setup_gitsigns
local setup_test_repo = helpers.setup_test_repo
local test_config = helpers.test_config
local eq_path = helpers.eq_path
local scratch --- @type string
local test_file --- @type string

helpers.env()

local function refresh_paths()
  scratch = helpers.scratch
  test_file = helpers.test_file
end

describe('qflist', function()
  before_each(function()
    clear()
    refresh_paths()
    helpers.chdir_tmp()
  end)

  after_each(function()
    cleanup()
  end)

  it('diffs renamed files against their base path when using a base revision', function()
    setup_test_repo()
    command('cd ' .. scratch)
    setup_gitsigns(vim.tbl_extend('force', test_config, { base = 'HEAD' }))

    local renamed = test_file .. '2'
    git('mv', test_file, renamed)
    exec_lua(function(path)
      local lines = vim.fn.readfile(path)
      lines[2] = 'renamed and edited'
      vim.fn.writefile(lines, path)
    end, renamed)

    exec_lua(function()
      require('gitsigns.actions').setqflist('all', { open = false })
    end)

    helpers.expectf(function()
      local items, names, texts = exec_lua(function()
        local items0 = vim.fn.getqflist()
        local names0 = {} --- @type string[]
        local texts0 = {} --- @type string[]
        for i, item in ipairs(items0) do
          names0[i] = item.filename or vim.api.nvim_buf_get_name(item.bufnr)
          texts0[i] = item.text
        end
        return items0, names0, texts0
      end) --- @type vim.quickfix.entry[], string[], string[]

      eq(1, #items)
      eq_path(renamed, names[1])
      eq(true, texts[1]:match('^Changed') ~= nil)
    end)
  end)

  it('includes deleted tracked files in setqflist all', function()
    setup_test_repo()
    command('cd ' .. scratch)
    setup_gitsigns(test_config)

    git('rm', test_file)

    exec_lua(function()
      require('gitsigns.actions').setqflist('all', { open = false })
    end)

    helpers.expectf(function()
      local items, names, texts = exec_lua(function()
        local items0 = vim.fn.getqflist()
        local names0 = {} --- @type string[]
        local texts0 = {} --- @type string[]
        for i, item in ipairs(items0) do
          names0[i] = item.filename or vim.api.nvim_buf_get_name(item.bufnr)
          texts0[i] = item.text
        end
        return items0, names0, texts0
      end) --- @type vim.quickfix.entry[], string[], string[]

      eq(1, #items)
      eq_path(test_file, names[1])
      eq(true, texts[1]:match('^Removed') ~= nil)
    end)
  end)

  it('includes changes from multiple files with threaded diff', function()
    local lines = { 'alpha', 'beta', 'gamma', 'delta', 'epsilon' }
    setup_test_repo({ test_file_text = lines })
    command('cd ' .. scratch)

    local second = scratch .. '/second.txt'
    helpers.write_to_file(second, lines)
    git('add', second)
    git('commit', '-m', 'Add second file')

    lines[3] = 'GAMMA'
    helpers.write_to_file(test_file, lines)
    helpers.write_to_file(second, lines)
    setup_gitsigns(vim.tbl_extend('force', test_config, {
      _threaded_diff = true,
      diff_opts = { linematch = 0 },
    }))

    exec_lua(function()
      require('gitsigns.actions').setqflist('all', { open = false })
    end)

    helpers.expectf(function()
      local names = exec_lua(function()
        return vim.tbl_map(function(item)
          local name = item.filename or vim.api.nvim_buf_get_name(item.bufnr)
          return vim.fs.basename(name) .. ':' .. item.lnum
        end, vim.fn.getqflist())
      end)
      table.sort(names)
      local expected = { vim.fs.basename(test_file) .. ':3', 'second.txt:3' }
      table.sort(expected)
      eq(expected, names)
    end)
  end)

  it('includes untracked files inside untracked directories in setqflist all', function()
    setup_test_repo()
    command('cd ' .. scratch)
    setup_gitsigns(test_config)

    local untracked = scratch .. '/newdir/untracked.lua'
    helpers.write_to_file(untracked, { 'untracked' })

    exec_lua(function()
      require('gitsigns.actions').setqflist('all', { open = false })
    end)

    helpers.expectf(function()
      local names = exec_lua(function()
        return vim.tbl_map(function(item)
          return item.filename or vim.api.nvim_buf_get_name(item.bufnr)
        end, vim.fn.getqflist())
      end) --- @type string[]

      eq(1, #names)
      eq_path(untracked, names[1])
    end)
  end)

  it('follows Git CRLF normalization in setqflist all', function()
    local lines = { 'one', 'two', 'three', 'four', 'five' }
    setup_test_repo({ test_file_text = lines })
    command('cd ' .. scratch)
    setup_gitsigns(test_config)

    -- The index stores LF and the working tree has CRLF, so only line 3 differs.
    git('config', 'core.autocrlf', 'true')
    lines[3] = 'THREE'
    helpers.write_to_file(test_file, lines, { newline = '\r\n' })

    exec_lua(function()
      require('gitsigns.actions').setqflist('all', { open = false })
    end)

    helpers.expectf(function()
      local texts = exec_lua(function()
        return vim.tbl_map(function(item)
          return item.text
        end, vim.fn.getqflist())
      end) --- @type string[]

      eq({ 'Changed (-3 +3): THREE' }, texts)
    end)
  end)

  it('keeps CRLF that Git stores in the index in setqflist all', function()
    local lines = { 'one', 'two', 'three', 'four', 'five' }
    setup_test_repo({ test_file_text = lines, no_add = true })
    command('cd ' .. scratch)
    setup_gitsigns(test_config)

    -- Git does not convert a file whose index entry already has CRLF.
    helpers.write_to_file(test_file, lines, { newline = '\r\n' })
    git('add', test_file)
    git('commit', '-m', 'Add CRLF file')
    git('config', 'core.autocrlf', 'true')
    lines[3] = 'THREE'
    helpers.write_to_file(test_file, lines, { newline = '\r\n' })

    exec_lua(function()
      require('gitsigns.actions').setqflist('all', { open = false })
    end)

    helpers.expectf(function()
      local texts = exec_lua(function()
        return vim.tbl_map(function(item)
          return item.text
        end, vim.fn.getqflist())
      end) --- @type string[]

      eq(1, #texts)
      eq(true, texts[1]:match('^Changed %(%-3 %+3%)') ~= nil)
    end)
  end)

  it('looks up the CRLF rules of all files at once in setqflist all', function()
    local lines = { 'one', 'two', 'three', 'four', 'five' }
    setup_test_repo({ test_file_text = lines, no_add = true })
    command('cd ' .. scratch)
    setup_gitsigns(test_config)

    local nested = scratch .. '/sub/nested.txt'
    local raw = scratch .. '/raw.txt'
    local crlf = scratch .. '/crlf.txt'
    local untracked = scratch .. '/untracked.txt'

    helpers.write_to_file(scratch .. '/.gitattributes', { 'raw.txt -text' })
    helpers.write_to_file(test_file, lines)
    helpers.write_to_file(nested, lines)
    helpers.write_to_file(raw, lines)
    -- Git does not convert a file whose index entry already has CRLF.
    helpers.write_to_file(crlf, lines, { newline = '\r\n' })
    git('add', '.')
    git('commit', '-m', 'Add files')
    git('config', 'core.autocrlf', 'true')

    lines[3] = 'THREE'
    for _, file in ipairs({ test_file, nested, raw, crlf, untracked }) do
      helpers.write_to_file(file, lines, { newline = '\r\n' })
    end

    command('Gitsigns clear_debug')
    exec_lua(function()
      require('gitsigns.actions').setqflist('all', { open = false })
    end)

    helpers.expectf(function()
      local texts = exec_lua(function()
        local ret = {} --- @type table<string,string>
        for _, item in ipairs(vim.fn.getqflist()) do
          local name = item.filename or vim.api.nvim_buf_get_name(item.bufnr)
          ret[vim.fs.basename(name)] = item.text
        end
        return ret
      end) --- @type table<string,string>

      local function text(file)
        return texts[vim.fs.basename(file)]
      end

      -- Converted: Git stores LF.
      eq('Changed (-3 +3): THREE', text(test_file))
      eq('Changed (-3 +3): THREE', text(nested))
      eq('Added   (-0,0 +1,5): one', text(untracked))
      -- Not converted: the index has CRLF, or the file has the `-text` attribute.
      eq(true, text(crlf):match('^Changed %(%-3 %+3%)') ~= nil)
      eq(true, text(raw):match('^Changed %(%-1,5 %+1,5%)') ~= nil)
    end)

    --- @param needle string
    --- @return integer
    local function count(needle)
      return #vim.tbl_filter(function(msg)
        return msg:find(needle, 1, true) ~= nil
      end, helpers.debug_messages())
    end

    -- One Git call for the line endings of all files, and one for `core.autocrlf`.
    eq(1, count('ls-files --stage --others --exclude-standard --eol'))
    eq(1, count('core\\.autocrlf'))
  end)
end)
