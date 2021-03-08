local M = {
  debug_mode = false,
  messages: {string} = {}
}

function M.dprint(msg: string, bufnr: number, caller: string)
  if not M.debug_mode then
    return
  end
  local name = caller or debug.getinfo(1, 'n').name or ''
  table.insert(M.messages, string.format('%s(%s): %s', name, bufnr, msg))
end

return M
