--- @diagnostic disable: global-in-non-module, redundant-parameter
local helpers = require('test.gs_helpers')

local clear = helpers.clear
local eq = helpers.eq
local exec_lua = helpers.exec_lua

helpers.env()

describe('debounce', function()
  before_each(function()
    clear()
    helpers.setup_path()
  end)

  it('closes the timer even if the function errors', function()
    exec_lua(function()
      local uv = vim.uv or vim.loop ---@diagnostic disable-line: deprecated

      _G._debounce_close_called = 0

      local orig_new_timer = uv.new_timer

      uv.new_timer = function(...)
        local t = assert(orig_new_timer(...))
        local proxy = { _t = t }

        function proxy:start(...)
          return self._t:start(...)
        end

        function proxy:close(...)
          _G._debounce_close_called = _G._debounce_close_called + 1
          return self._t:close(...)
        end

        return proxy
      end

      local debounce_trailing = require('gitsigns.debounce').debounce_trailing
      local debounced = debounce_trailing(1, function()
        error('GS_DEBOUNCE_TEST_CLOSE')
      end)
      debounced()
    end)

    helpers.expectf(function()
      eq(1, exec_lua('return _G._debounce_close_called'))
    end)
  end)

  it('prints a full stacktrace if the function errors', function()
    exec_lua(function()
      local debounce_trailing = require('gitsigns.debounce').debounce_trailing
      local debounced = debounce_trailing(1, function()
        error('GS_DEBOUNCE_TEST_STACK')
      end)
      debounced()
    end)

    helpers.expectf(function()
      local messages = exec_lua(function()
        return vim.api.nvim_exec2('messages', { output = true }).output
      end) ---@type string
      assert(messages:match('debounce_spec.lua:%d+: GS_DEBOUNCE_TEST_STACK'), messages)
      assert(messages:match('stack traceback'), messages)
      assert(messages:match('lua/gitsigns/debounce.lua'), messages)
    end)
  end)

  it('debounces independently by hash key', function()
    exec_lua(function()
      local debounce_trailing = require('gitsigns.debounce').debounce_trailing

      _G._debounce_hash_calls = {}

      local debounced = debounce_trailing({
        timeout = 10,
        hash = 1,
      }, function(id, value)
        local t = _G._debounce_hash_calls[id] or { count = 0, value = nil }
        t.count = t.count + 1
        t.value = value
        _G._debounce_hash_calls[id] = t
      end)

      debounced('a', 1)
      debounced('a', 2)
      debounced('b', 3)
      debounced('b', 4)
    end)

    helpers.expectf(function()
      eq({
        a = { count = 1, value = 2 },
        b = { count = 1, value = 4 },
      }, exec_lua('return _G._debounce_hash_calls'))
    end)
  end)

  it('accepts a hash function for ids', function()
    exec_lua(function()
      local debounce_trailing = require('gitsigns.debounce').debounce_trailing

      _G._debounce_hash_fn_calls = {}

      local debounced = debounce_trailing({
        timeout = 10,
        hash = function(id)
          return id
        end,
      }, function(id, value)
        _G._debounce_hash_fn_calls[id] = (_G._debounce_hash_fn_calls[id] or 0) + 1
        _G._debounce_hash_fn_value = value
      end)

      debounced('a', 1)
      debounced('a', 2)
    end)

    helpers.expectf(function()
      eq(1, exec_lua("return _G._debounce_hash_fn_calls['a']"))
      eq(2, exec_lua('return _G._debounce_hash_fn_value'))
    end)
  end)
end)
