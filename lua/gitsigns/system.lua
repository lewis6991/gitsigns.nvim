local log = require('gitsigns.debug.log')

local M = {}

local system = vim.system or require('gitsigns.system.compat')

--- @param cmd string[]
--- @param opts vim.SystemOpts
--- @param on_exit fun(obj: vim.SystemCompleted)
--- @return vim.SystemObj
function M.system(cmd, opts, on_exit)
  local __FUNC__ = 'run_job'
  if log.debug_mode then
    log.dprint(table.concat(cmd, ' '))
  end
  return system(cmd, opts, on_exit)
end

return M
