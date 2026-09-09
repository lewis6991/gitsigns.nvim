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
end)
