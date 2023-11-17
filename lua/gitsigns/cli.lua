local async = require('gitsigns.async')
local void = require('gitsigns.async').void

local log = require('gitsigns.debug.log')
local dprintf = log.dprintf
local message = require('gitsigns.message')

local parse_args = require('gitsigns.cli.argparse').parse_args

local actions = require('gitsigns.actions')
local attach = require('gitsigns.attach')
local gs_debug = require('gitsigns.debug')

--- @type table<table<string,function>,boolean>
local sources = {
  [actions] = true,
  [attach] = false,
  [gs_debug] = false,
}

-- try to parse each argument as a lua boolean, nil or number, if fails then
-- keep argument as a string:
--
--    'false'      -> false
--    'nil'         -> nil
--    '100'         -> 100
--    'HEAD~300' -> 'HEAD~300'
local function parse_to_lua(a)
  if tonumber(a) then
    return tonumber(a)
  elseif a == 'false' or a == 'true' then
    return a == 'true'
  elseif a == 'nil' then
    return nil
  end
  return a
end

local M = {}

function M.complete(arglead, line)
  local words = vim.split(line, '%s+')
  local n = #words

  local matches = {}
  if n == 2 then
    for m, _ in pairs(sources) do
      for func, _ in pairs(m) do
        if not func:match('^[a-z]') then
          -- exclude
        elseif vim.startswith(func, arglead) then
          table.insert(matches, func)
        end
      end
    end
  elseif n > 2 then
    -- Subcommand completion
    local cmp_func = actions._get_cmp_func(words[2])
    if cmp_func then
      return cmp_func(arglead)
    end
  end
  return matches
end

local function print_nonnil(x)
  if x ~= nil then
    print(vim.inspect(x))
  end
end

local select = async.wrap(vim.ui.select, 3)

M.run = void(function(params)
  local __FUNC__ = 'cli.run'
  local pos_args_raw, named_args_raw = parse_args(params.args)

  local func = pos_args_raw[1]

  if not func then
    func = select(M.complete('', 'Gitsigns '), {}) --[[@as string]]
    if not func then
      return
    end
  end

  local pos_args = vim.tbl_map(parse_to_lua, vim.list_slice(pos_args_raw, 2))
  local named_args = vim.tbl_map(parse_to_lua, named_args_raw)
  local args = vim.tbl_extend('error', pos_args, named_args)

  dprintf(
    "Running action '%s' with arguments %s",
    func,
    vim.inspect(args, { newline = ' ', indent = '' })
  )

  local cmd_func = actions._get_cmd_func(func)
  if cmd_func then
    -- Action has a specialised mapping function from command form to lua
    -- function
    print_nonnil(cmd_func(args, params))
    return
  end

  for m, has_named in pairs(sources) do
    local f = m[func]
    if type(f) == 'function' then
      -- Note functions here do not have named arguments
      print_nonnil(f(unpack(pos_args), has_named and named_args or nil))
      return
    end
  end

  message.error('%s is not a valid function or action', func)
end)

return M
