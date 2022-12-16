local async = require('gitsigns.async')
local void = require('gitsigns.async').void

local gs_debug   = require("gitsigns.debug")
local dprintf    = gs_debug.dprintf

local parse_args = require('gitsigns.cli.argparse').parse_args

-- try to parse each argument as a lua boolean, nil or number, if fails then
-- keep argument as a string:
--
--   'false'    -> false
--   'nil'      -> nil
--   '100'      -> 100
--   'HEAD~300' -> 'HEAD~300'
local function parse_to_lua(a: string): any
  if tonumber(a) then
    return tonumber(a)
  elseif a == 'false' or a == 'true' then
    return a == 'true'
  elseif a == 'nil' then
    return nil
  end
  return a
end

local record M
  run : function(funcs: {string:function}, params: vim.api.UserCmdParams)
end

function M.complete(funcs: {string:function}, arglead: string, line: string): {string}
  local words = vim.split(line, '%s+')
  local n: integer = #words

  local actions = require('gitsigns.actions')
  local matches: {string} = {}
  if n == 2 then
    for _, m in ipairs{actions as {string:function}, funcs} do
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

M.run = void(function(funcs: {string:function}, params: vim.api.UserCmdParams)
  local pos_args_raw, named_args_raw = parse_args(params.args)

  local func = pos_args_raw[1]

  if not func then
    func = async.wrap(vim.ui.select, 3)(M.complete(funcs, '', 'Gitsigns '), {})
  end

  local pos_args = vim.tbl_map(parse_to_lua, vim.list_slice(pos_args_raw, 2)) as {any}
  local named_args = vim.tbl_map(parse_to_lua, named_args_raw) as {string:any}
  local args = vim.tbl_extend('error', pos_args, named_args)

  local actions = require('gitsigns.actions')
  local actions0 = actions as {string:function}

  dprintf("Running action '%s' with arguments %s", func, vim.inspect(args, {newline=' ', indent=''}))

  local cmd_func = actions._get_cmd_func(func)
  if cmd_func then
    -- Action has a specialised mapping function from command form to lua
    -- function
    cmd_func(args, params)
    return
  end

  if type(actions0[func]) == 'function' then
    actions0[func](unpack(pos_args), named_args)
    return
  end

  if type(funcs[func]) == 'function' then
    -- Note functions here do not have named arguments
    funcs[func](unpack(pos_args))
    return
  end

  error(string.format('%s is not a valid function or action', func))
end)

return M
