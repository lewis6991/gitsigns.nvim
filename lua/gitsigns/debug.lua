local dfile
local log = 'gitsigns.log'

local M = {}

function M.dprint(msg, bufnr, caller)
  local name = caller or debug.getinfo(2, 'n').name or ''
  if not dfile then
    print('Opening '..log)
    dfile = io.open(log, 'w')
    dfile:write('\n--------------------NEW SESSION--------------------\n\n')
  end
  dfile:write(string.format('%s(%s): %s\n', name, bufnr, msg))
  dfile:flush()
end

return M
