local levels = vim.log.levels

local M = {}

--- @type fun(fmt: string, ...: string)
M.warn = vim.schedule_wrap(function(fmt, ...)
  vim.notify(fmt:format(...), levels.WARN, { title = 'gitsigns' })
end)

--- @type fun(fmt: string, ...: string)
M.error = vim.schedule_wrap(function(fmt, ...)
  vim.notify(fmt:format(...), vim.log.levels.ERROR, { title = 'gitsigns' })
end)

--- @type fun(fmt: string, ...: string)
M.error_once = vim.schedule_wrap(function(fmt, ...)
  vim.notify_once(fmt:format(...), vim.log.levels.ERROR, { title = 'gitsigns' })
end)

return M
