local helpers = require('test.gs_helpers')

local eq = helpers.eq
local expectf = helpers.expectf

helpers.env()

describe('git locale', function()
  before_each(function()
    helpers.clear()
    helpers.setup_path()
  end)

  after_each(function()
    helpers.cleanup()
  end)

  it('attaches in fresh repos regardless of locale', function()
    helpers.setup_test_repo({ no_add = true })

    helpers.exec_lua(function()
      package.loaded['gitsigns.git.cmd'] = nil
      local orig_git_cmd = require('gitsigns.git.cmd')

      _G.gitsigns_git_envs = {}

      package.loaded['gitsigns.git.cmd'] = function(args, spec)
        spec = spec or {}

        local stdout, stderr, code = orig_git_cmd(args, spec)

        _G.gitsigns_git_envs[#_G.gitsigns_git_envs + 1] = {
          args = vim.deepcopy(args),
          env = vim.deepcopy(spec.env or {}),
        }

        return stdout, stderr, code
      end

      vim.env.LANG = 'zh_CN.UTF-8'
      vim.env.LC_ALL = 'zh_CN.UTF-8'
      vim.env.LC_MESSAGES = nil
      vim.env.LANGUAGE = nil
    end)

    local config = vim.deepcopy(helpers.test_config)
    config.watch_gitdir = { interval = 100 }
    helpers.setup_gitsigns(config)

    helpers.edit(helpers.test_file)

    helpers.check({
      status = { head = '', added = 18, changed = 0, removed = 0 },
    })

    expectf(function()
      return helpers.exec_lua(function()
        return _G.gitsigns_git_envs ~= nil and #_G.gitsigns_git_envs > 0
      end)
    end)

    local envs = helpers.exec_lua(function()
      return _G.gitsigns_git_envs
    end)

    for _, item in ipairs(envs) do
      eq('C', item.env.LC_ALL)
      eq('C', item.env.LANGUAGE)
    end
  end)
end)
