local log = require('gitsigns.debug.log')

local M = {
  job_cnt = 0,
}

local system = vim.system or require('gitsigns.system.compat')

--- @param cmd string[]
--- @param opts SystemOpts
--- @param on_exit fun(obj: vim.SystemCompleted)
--- @return vim.SystemObj
function M.system(cmd, opts, on_exit)
  local __FUNC__ = 'run_job'
  if log.debug_mode then
    log.dprint(table.concat(cmd, ' '))
  end
  M.job_cnt = M.job_cnt + 1
  return system(cmd, opts, on_exit)
end

return M
