local M = {}

-- local eprint = require('gitsigns.debug.log').eprint

--- @type fun(fmt: string, ...: string)
M.warn = vim.schedule_wrap(function(s, ...)
  vim.notify(s:format(...), vim.log.levels.WARN, { title = 'gitsigns' })
end)

--- @type fun(fmt: string, ...: string)
M.error = function(s, ...)
  local msg = s:format(...) --- @type string
  -- eprint(msg)
  vim.schedule(function()
    vim.notify(msg, vim.log.levels.ERROR, { title = 'gitsigns' })
  end)
end

--- @type fun(fmt: string, ...: string)
M.error_once = function(s, ...)
  local msg = s:format(...) --- @type string
  -- eprint(msg)
  vim.schedule(function()
    vim.notify_once(msg, vim.log.levels.ERROR, { title = 'gitsigns' })
  end)
end

return M
