local helpers = require('test.gs_helpers')

local eq = helpers.eq

helpers.env()

describe('attach', function()
  before_each(function()
    helpers.clear()
  end)

  after_each(function()
    helpers.cleanup()
  end)

  it(
    'does not crash when the buffer is wiped while attach is suspended in on_attach_pre',
    function()
      helpers.setup_test_repo()

      -- Can't build `_on_attach_pre` on the test-runner side and hand it to
      -- setup_gitsigns(): functions aren't msgpack-serializable, so a closure
      -- can't cross the RPC boundary as a plain argument. Construct it inside
      -- the exec_lua body instead, which runs directly in the remote Nvim.
      -- setup_path() is required first (mirroring setup_gitsigns()) so that
      -- require('gitsigns') resolves via an absolute package.path rather than
      -- the relative one set on the command line.
      helpers.setup_path()
      helpers.exec_lua(function(config0)
        -- Freeze instead of resolving immediately. This simulates a slow (or,
        -- as here, indefinitely delayed) `_on_attach_pre` integration -- e.g.
        -- a worktree/yadm lookup -- racing against something that deletes the
        -- buffer, such as a plugin that opens a scratch buffer and force-wipes
        -- it (`:bwipeout!`) once done with it.
        config0._on_attach_pre = function(_bufnr, callback)
          _G.gitsigns_test_attach_cb = callback
        end

        local maps = config0.on_attach --[[@as [string,string,string][] ]]
        config0.on_attach = function(bufnr)
          for _, map in ipairs(maps) do
            vim.keymap.set(map[1], map[2], map[3], { buffer = bufnr })
          end
        end

        require('gitsigns').setup(config0)
        vim.o.diffopt = 'internal,filler,closeoff'
      end, vim.deepcopy(helpers.test_config))

      helpers.edit(helpers.test_file)

      helpers.expectf(function()
        return helpers.exec_lua(function()
          return _G.gitsigns_test_attach_cb ~= nil
        end)
      end)

      local result = helpers.exec_lua(function()
        local bufnr = vim.api.nvim_get_current_buf()

        -- Wipe the buffer while gitsigns' attach coroutine is suspended.
        vim.api.nvim_buf_delete(bufnr, { force = true })

        -- Resume it: this must not raise "Invalid buffer id".
        local ok, err = pcall(_G.gitsigns_test_attach_cb)
        _G.gitsigns_test_attach_cb = nil

        local stale_cache_bufnr --- @type integer?
        for cached_bufnr in pairs(require('gitsigns.cache').cache) do
          if not vim.api.nvim_buf_is_valid(cached_bufnr) then
            stale_cache_bufnr = cached_bufnr
          end
        end

        return {
          ok = ok,
          err = err and tostring(err) or nil,
          stale_cache_bufnr = stale_cache_bufnr,
        }
      end)

      eq(true, result.ok, result.err)
      eq(nil, result.stale_cache_bufnr, 'a deleted buffer must not remain in the attach cache')
    end
  )
end)
