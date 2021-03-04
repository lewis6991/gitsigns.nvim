local M = {
  debug_mode = false
}

function M.dprint(msg: string, bufnr: number, caller: string)
  if not M.debug_mode then
    return
  end
  local name = caller or debug.getinfo(1, 'n').name or ''
  vim.schedule(function()
    print(string.format('%s(%s): %s\n', name, bufnr, msg))
  end)
end

return M
