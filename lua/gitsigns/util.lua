local Job = require('plenary.job')

local gsd = require("gitsigns.debug")

local M = {}




M.job_cnt = 0

function M.path_exists(path)
   return vim.loop.fs_stat(path) and true or false
end

function M.run_job(job_spec)
   if gsd.debug_mode then
      local cmd = job_spec.command .. ' ' .. table.concat(job_spec.args, ' ')
      gsd.dprint(cmd)
   end
   Job:new(job_spec):start()
   M.job_cnt = M.job_cnt + 1
end

function M.get_jit_os()
   if jit then
      return jit.os:lower()
   end
   return
end

M.path_sep = (function()
   local jit_os = M.get_jit_os()
   if jit_os then
      if jit_os == 'linux' or jit_os == 'osx' then
         return '/'
      else
         return '\\'
      end
   else
      return package.config:sub(1, 1)
   end
end)()

function M.dirname(file)
   return file:match(string.format('^(.+)%s[^%s]+', M.path_sep, M.path_sep))
end

return M
