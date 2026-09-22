local helpers = require('test.gs_helpers')

local api = helpers.api
local eq = helpers.eq
local exec_lua = helpers.exec_lua

helpers.env()

describe('unified syntax', function()
  before_each(function()
    helpers.clear()
    helpers.chdir_tmp()
    helpers.setup_gitsigns(helpers.test_config)
    helpers.setup_test_repo()
  end)

  for _, fixture in ipairs({
    { name = 'Lua', file = 'example.lua', lines = { '-- unchanged', 'local value = 1' }, row = 1 },
    {
      name = 'injected Lua',
      file = 'example.md',
      lines = { '# Example', '', '```lua', 'local value = 1', '```' },
      row = 3,
    },
  }) do
    it('highlights deleted ' .. fixture.name .. ' text on the first render', function()
      helpers.require_source_hls()

      local path = helpers.scratch .. '/' .. fixture.file
      helpers.write_to_file(path, fixture.lines)
      helpers.git('add', fixture.file)
      exec_lua(function()
        vim.api.nvim_create_autocmd('FileType', {
          pattern = { 'lua', 'markdown' },
          callback = function(args)
            -- Starting the highlighter need not parse a hidden revision buffer.
            vim.treesitter.start(args.buf)
          end,
        })
        vim.cmd('filetype on')
      end)
      helpers.edit(path)
      helpers.wait_for_attach()
      api.nvim_buf_set_lines(0, fixture.row, fixture.row + 1, false, { 'local value = 2' })
      api.nvim_command('Gitsigns diffthis unified=true')

      helpers.expectf(function()
        eq(
          true,
          exec_lua(function()
            local view = require('gitsigns.unified').get_view()
            return view ~= nil and view.hunks ~= nil
          end)
        )
      end)

      local keyword_highlighted = exec_lua(function()
        local view = assert(require('gitsigns.unified').get_view())
        local marks = vim.api.nvim_buf_get_extmarks(0, view.ns, 0, -1, { details = true })
        for _, mark in ipairs(marks) do
          for _, line in ipairs(mark[4].virt_lines or {}) do
            for _, chunk in ipairs(line) do
              if chunk[1] == 'local' and vim.tbl_contains(chunk[2], '@keyword.lua') then
                return true
              end
            end
          end
        end
        return false
      end)
      eq(true, keyword_highlighted, 'Deleted local keyword should have Tree-sitter highlighting')
    end)
  end
end)
