local Job = require('plenary/job')

local gsd = require("gitsigns/debug")

local M = {
  job_cnt = 0
}

function M.path_exists(path: string): boolean
  return vim.loop.fs_stat(path) and true or false
end

function M.run_job(job_spec: Job.JobSpec)
  if gsd.debug_mode then
    local cmd: string = job_spec.command..' '..table.concat(job_spec.args, ' ')
    gsd.dprint('Running: '..cmd)
  end
  Job:new(job_spec):start()
  M.job_cnt = M.job_cnt + 1
end

return M
