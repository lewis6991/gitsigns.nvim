--- @diagnostic disable: global-in-non-module, redundant-parameter
local helpers = require('test.gs_helpers')

local clear = helpers.clear
local eq = helpers.eq
local exec_lua = helpers.exec_lua

helpers.env()

describe('debounce', function()
  local initialized = false

  before_each(function()
    if initialized then
      return
    end

    clear()
    helpers.setup_path()
    initialized = true
  end)

  after_each(function()
    exec_lua(function()
      local uv = vim.uv

      if _G._debounce_orig_new_timer then
        uv.new_timer = _G._debounce_orig_new_timer
        _G._debounce_orig_new_timer = nil
      end

      _G._debounce_close_called = nil
      _G._debounce_hash_calls = nil
      _G._debounce_hash_fn_calls = nil
      _G._debounce_hash_fn_value = nil
      package.loaded['gitsigns.debounce'] = nil
    end)
  end)

  it('closes the timer even if the function errors', function()
    exec_lua(function()
      local uv = vim.uv

      _G._debounce_close_called = 0

      local orig_new_timer = uv.new_timer
      _G._debounce_orig_new_timer = orig_new_timer

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
      messages = messages:gsub('\\', '/')
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

  for _, async_module in ipairs({ 'gitsigns.async', 'vim.async' }) do
    for _, fail_start in ipairs({ false, true }) do
      for _, schedule in ipairs({ false, true }) do
        local name = ('throttle recovers from %s errors with schedule=%s (%s)'):format(
          fail_start and 'async startup' or 'call',
          tostring(schedule),
          async_module
        )
        it(name, function()
          local supported = exec_lua(function(module)
            local ok = pcall(require, module)
            return ok
          end, async_module)
          if not supported then
            helpers.pending('requires ' .. async_module)
          end

          local result = exec_lua(function(module, schedule0, fail_start0)
            local async = require(module)
            local original = package.loaded['gitsigns.async']
            package.loaded['gitsigns.async'] = async
            local ok, debounce = pcall(require, 'gitsigns.debounce')
            package.loaded['gitsigns.async'] = original
            assert(ok, debounce)

            local gate = async.event and async.event()
            local release --- @type fun()?
            local calls = 0
            local failure = {}
            local start_operation = async.wrap(1, function(_callback)
              error(failure)
            end)
            local function fail_update()
              if gate then
                gate:wait()
              else
                -- vim.async has no event helper; hold its callback instead.
                async.await(function(callback)
                  release = callback
                end)
              end
              if fail_start0 then
                start_operation()
              else
                error(failure)
              end
            end
            local function refresh_buffer()
              fail_update()
            end
            local throttled = debounce.throttle_async({ schedule = schedule0 }, function()
              calls = calls + 1
              if calls == 1 then
                refresh_buffer()
              end
              async.await(vim.schedule)
            end)

            local first = async.run(throttled)
            -- Call while suspended to queue or drop an update.
            async.run(throttled):wait(1000)
            if gate then
              gate:set()
            else
              assert(release)()
            end
            local success, err = first:pwait(1000)
            local traceback = first:traceback()
            assert(traceback:find("in function 'fail_update'", 1, true), traceback)
            assert(traceback:find("in function 'refresh_buffer'", 1, true), traceback)

            -- A later update must still run and yield after the error.
            async.run(throttled):wait(1000)
            return { calls = calls, failed = not success, same_error = err == failure }
          end, async_module, schedule, fail_start)

          eq({ calls = 2, failed = true, same_error = true }, result)
        end)
      end
    end
  end
end)
