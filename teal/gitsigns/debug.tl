local M = {
  debug_mode = false,
  messages: {string} = {}
}

local function getvarvalue(name: string): any
  local value: any
  local found: boolean

  -- try local variables
  local i = 1
  while true do
    local n, v = debug.getlocal(3 as function, i) as (string, any)
    if not n then break end
    if n == name then
      value = v
      found = true
    end
    i = i + 1
  end
  if found then return value end

  -- try upvalues
  local func = debug.getinfo(3).func as function
  i = 1
  while true do
    local n, v = debug.getupvalue(func, i) as (string, any)
    if not n then break end
    if n == name then return v end
    i = i + 1
  end

  -- not found; get global
  return getfenv(func)[name]
end

function M.dprint(obj: any, caller: string)
  if not M.debug_mode then
    return
  end
  local msg = obj is string and obj or vim.inspect(obj)
  local name: string = caller
  if not name then
    local name0 = debug.getinfo(2, 'n').name or ''
    name = name0:gsub('(.*)%d+$', '%1')
  end
  local msg2: string

  local bufnr = getvarvalue('bufnr') or getvarvalue('cbuf')
  if bufnr then
    msg2 = string.format('%s(%s): %s', name, bufnr, msg)
  else
    msg2 = string.format('%s: %s', name, msg)
  end
  table.insert(M.messages, msg2)
end

function M.eprint(msg: string)
  local info = debug.getinfo(2, 'Sl')
  if info then
    msg = string.format('(ERROR) %s(%d): %s', info.short_src, info.currentline, msg)
  end
  M.messages[#M.messages+1] = msg
  if M.debug_mode then
    error(msg)
  else
    -- On windows print() crashes in callback threads
    vim.schedule(function()
      print('error: ' .. msg)
    end)
  end
end

function M.add_debug_functions(cache: any): {string:function}
  local R: {string:function} = {}
  R.dump_cache = function(): any
    vim.api.nvim_echo({{vim.inspect(cache, {
      process = function(raw_item: any, path: {string}): any
        if path[#path] == vim.inspect.METATABLE then
          return nil
        elseif raw_item is function then
          return nil
        elseif raw_item is table then
          local key <const> = path[#path]
          if key == 'compare_text' then
            local item <const> = raw_item as {string}
            return { '...', length=#item, head=item[1] }
          elseif not vim.tbl_isempty(raw_item) and vim.tbl_contains({
            'staged_diffs' }, key) then
            return { '...', length=#vim.tbl_keys(raw_item) }
          elseif key == 'pending_signs' then
            local keys = vim.tbl_keys(raw_item)
            local max <const> = 100
            if #keys > max then
              keys.length = #keys
              for i = max, #keys do
                keys[i] = nil
              end
              keys[max] = '...'
            end
            return keys
          end
        end
        return raw_item
      end
    })}}, false, {})
    return cache
  end

  R.debug_messages = function(noecho: boolean): {string}
    if not noecho then
      for _, m in ipairs(M.messages) do
        vim.api.nvim_echo({{m}}, false, {})
      end
    end
    return M.messages
  end

  R.clear_debug = function()
    M.messages = {}
  end

  return R
end

return M
