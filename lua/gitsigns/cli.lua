local actions = require('gitsigns.actions')
local argparse = require('gitsigns.cli.argparse')
local async = require('gitsigns.async')
local attach = require('gitsigns.attach')
local Debug = require('gitsigns.debug')
local log = require('gitsigns.debug.log')
local message = require('gitsigns.message')

--- @type table<table<string,function>,boolean>
local sources = {
  [actions] = true,
  [attach] = false,
  [Debug] = false,
}

--- try to parse each argument as a lua boolean, nil or number, if fails then
--- keep argument as a string:
---
---    'false'      -> false
---    'nil'         -> nil
---    '100'         -> 100
---    'HEAD~300' -> 'HEAD~300'
--- @param a string
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

M.run = async.create(1, function(params)
  local __FUNC__ = 'cli.run'
  local pos_args_raw, named_args_raw = argparse.parse_args(params.args)

  local func = pos_args_raw[1]

  if not func then
    func = async.await(3, vim.ui.select, M.complete('', 'Gitsigns '), {}) --[[@as string]]
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

  for m, has_named in pairs(sources) do
    local f = m[func]
    if type(f) == 'function' then
      -- Note functions here do not have named arguments
      f(unpack(pos_args), has_named and named_args or nil)
      return
    end
  end

  message.error('%s is not a valid function or action', func)
end)

return M
