local M = {
  debug_mode = false,
  messages: {string} = {}
}

function M.dprint(msg: string, bufnr: number, caller: string)
  if not M.debug_mode then
    return
  end
  local name = caller or debug.getinfo(2, 'n').name or ''
  local msg2: string
  if bufnr then
    msg2 = string.format('%s(%s): %s', name, bufnr, msg)
  else
    msg2 = string.format('%s: %s', name, msg)
  end
  table.insert(M.messages, msg2)
end

function M.eprint(msg: string)
  -- On windows print() crashes in callback threads
  if vim.in_fast_event() then
    vim.schedule(function()
      print('error: ' .. msg)
    end)
  else
    print('error: ' .. msg)
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
            return { length=#item, head=item[1] }
          elseif key == 'hunks' then
            local ret = {}
            for _, h in ipairs(raw_item as {table}) do
              local a = vim.deepcopy(h)
              a.added = nil
              a.removed = nil
              ret[#ret+1] = a
            end
            return ret
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
