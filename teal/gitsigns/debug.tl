local M = {}

function M.dprint(msg: string, bufnr: number, caller: string)
  local name = caller or debug.getinfo(2, 'n').name or ''
  print(string.format('%s(%s): %s\n', name, bufnr, msg))
end

return M
