local actions = require('gitsigns.actions')
local argparse = require('gitsigns.cli.argparse')
local async = require('gitsigns.async')
local attach = require('gitsigns.attach')
local Debug = require('gitsigns.debug')
local log = require('gitsigns.debug.log')
local message = require('gitsigns.message')

--- @type table<string,function>[]
local sources = { actions, attach, Debug }

--- try to parse each argument as a lua boolean, nil or number, if fails then
--- keep argument as a string:
---
---    'false'      -> false
---    'nil'         -> nil
---    '100'         -> 100
---    'HEAD~300' -> 'HEAD~300'
--- @param a string|boolean
--- @return boolean|number|string?
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
    for _, m in ipairs(sources) do
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
    local cmp_func = actions._get_cmp_func(assert(words[2]))
    if cmp_func then
      return cmp_func(arglead)
    end
  end
  return matches
end

--- @async
--- @param params vim.api.keyset.create_user_command.command_args
function M.run(params)
  local __FUNC__ = 'cli.run'
  local pos_args_raw, named_args_raw = argparse.parse_args(params.args)

  local func = pos_args_raw[1]

  if not func then
    func = async.await(3, function(...)
      -- Need to wrap vim.ui.select as Snacks version of vim.ui.select returns a
      -- module table with a close method which conflicts with the async lib
      vim.ui.select(...)
    end, M.complete('', 'Gitsigns '), {}) --[[@as string]]
    if not func then
      return
    end
  end

  local pos_args = vim.tbl_map(parse_to_lua, vim.list_slice(pos_args_raw, 2))
  local named_args = vim.tbl_map(parse_to_lua, named_args_raw)
  local args = vim.tbl_extend('error', pos_args, named_args)

  log.dprintf(
    "Running action '%s' with arguments %s",
    func,
    vim.inspect(args, { newline = ' ', indent = '' })
  )

  local cmd_func = actions._get_cmd_func(func)
  if cmd_func then
    -- Action has a specialised mapping function from command form to lua
    -- function
    cmd_func(args, params)
    return
  end

  for _, m in ipairs(sources) do
    local f = m[func]
    if type(f) == 'function' then
      -- Note functions here do not have named arguments
      f(unpack(pos_args))
      return
    end
  end

  message.error('%s is not a valid function or action', func)
end

return M
