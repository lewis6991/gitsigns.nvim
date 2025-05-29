local log = require('gitsigns.debug.log')

local M = {}

-- compat module contains 0.11 fixes.
local system = vim.fn.has('nvim-0.11.2') == 1 and vim.system or require('gitsigns.system.compat')

--- @param cmd string[]
--- @param opts vim.SystemOpts
--- @param on_exit fun(obj: vim.SystemCompleted)
--- @return vim.SystemObj
function M.system(cmd, opts, on_exit)
  local __FUNC__ = 'run_job'
  log.dprint(unpack(cmd))
  return system(cmd, opts, on_exit)
end

return M
