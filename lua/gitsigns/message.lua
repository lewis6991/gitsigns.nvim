

local M = {}




M.warn = vim.schedule_wrap(function(s, ...)
   vim.notify(s:format(...), vim.log.levels.WARN, { title = 'gitsigns' })
end)

M.error = vim.schedule_wrap(function(s, ...)
   vim.notify(s:format(...), vim.log.levels.ERROR, { title = 'gitsigns' })
end)

return M
