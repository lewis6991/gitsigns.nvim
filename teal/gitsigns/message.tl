local type MsgFun = function(string, ...: any)

local record M
  warn  : MsgFun
  error : MsgFun
end

M.warn = vim.schedule_wrap(function(s: string, ...:any)
  vim.notify(s:format(...), vim.log.levels.WARN, {title = 'gitsigns'})
end) as MsgFun

M.error = vim.schedule_wrap(function(s: string, ...:any)
  vim.notify(s:format(...), vim.log.levels.ERROR, {title = 'gitsigns'})
end) as MsgFun

return M
