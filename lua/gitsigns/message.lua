
local M = {}

function M.warn(s, ...)
   vim.notify(s:format(...), vim.log.levels.WARN, { title = 'gitsigns' })
end

return M
