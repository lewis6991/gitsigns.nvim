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

local jit_os

if jit then
   jit_os = jit.os:lower()
end

M.is_unix = (function()
   if jit_os == 'linux' or jit_os == 'osx' or jit_os == 'bsd' then
      return true
   end
   return false
end)()

function M.dirname(file)
   return file:match(string.format('^(.+)%s[^%s]+', M.path_sep, M.path_sep))
end

function M.file_lines(file)
   local text = {}
   for line in io.lines(file) do
      text[#text + 1] = line
   end
   return text
end

M.path_sep = (function()
   if jit_os then
      if M.is_unix then
         return '/'
      end
      return '\\'
   end
   return package.config:sub(1, 1)
end)()

function M.tmpname()
   if M.is_unix then
      return os.tmpname()
   end
   return vim.fn.tempname()
end

function M.get_relative_time(timestamp)
   local current_timestamp = os.time()
   local elapsed = current_timestamp - timestamp

   if elapsed == 0 then
      return 'a while ago'
   end

   local minute_seconds = 60
   local hour_seconds = minute_seconds * 60
   local day_seconds = hour_seconds * 24
   local month_seconds = day_seconds * 30
   local year_seconds = month_seconds * 12

   local to_relative_string = function(time, divisor, time_word)
      local num = math.floor(time / divisor)
      if num > 1 then
         time_word = time_word .. 's'
      end

      return num .. ' ' .. time_word .. ' ago'
   end

   if elapsed < minute_seconds then
      return to_relative_string(elapsed, 1, 'second')
   elseif elapsed < hour_seconds then
      return to_relative_string(elapsed, minute_seconds, 'minute')
   elseif elapsed < day_seconds then
      return to_relative_string(elapsed, hour_seconds, 'hour')
   elseif elapsed < month_seconds then
      return to_relative_string(elapsed, day_seconds, 'day')
   elseif elapsed < year_seconds then
      return to_relative_string(elapsed, month_seconds, 'month')
   else
      return to_relative_string(elapsed, year_seconds, 'year')
   end
end

return M
