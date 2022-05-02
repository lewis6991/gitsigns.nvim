local helpers = require('test.gs_helpers')
local exec_lua = helpers.exec_lua
local setup_gitsigns  = helpers.setup_gitsigns
local clear           = helpers.clear

local function get_tests(pattern)
  local modules = exec_lua[[return vim.tbl_keys(package.loaded)]]

  local tests = {}
  for _, mod in ipairs(modules) do
    if mod:match(pattern) then
      tests[mod] = exec_lua([[
        local mod = package.loaded[...]
        if type(mod) == 'table' then
          return vim.tbl_keys(mod._tests or {})
        end
        return {}
      ]], mod)
    end
  end
  return tests
end

local function run_test(mod, test)
  return unpack(exec_lua([[
    local mod, test = ...
    return {pcall(package.loaded[mod]._tests[test])}
   ]], mod, test))
end

local function load(mod)
  exec_lua([[require(...)]], mod)
end

describe('unit test', function()
  clear()
  exec_lua('package.path = ...', package.path)
  exec_lua('_TEST = true')
  setup_gitsigns{debug_mode = true}

  -- Add modules which have unit tests
  -- TODO(lewis6991): automate
  load('gitsigns.test')

  local gs_tests = get_tests('^gitsigns')

  for mod, tests in pairs(gs_tests) do
    for _, test in ipairs(tests) do
      it(mod..':'..test, function()
        local ok, err = run_test(mod, test)

        if not ok then
          local msgs = helpers.debug_messages()
          for _, msg in ipairs(msgs) do
            print(msg)
          end
          error(err)
        end
      end)
    end

  end
end)
