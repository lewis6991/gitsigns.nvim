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

function M.warning(msg: string)
  local msg1 = '[gitsigns] Warning: '..msg
  -- On windows print() crashes in callback threads
  if vim.in_fast_event() then
    vim.schedule(function()
      print(msg1)
    end)
  else
    print(msg1)
  end
end

return M
