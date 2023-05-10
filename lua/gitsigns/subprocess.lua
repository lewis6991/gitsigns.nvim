local log = require("gitsigns.debug.log")
local guv = require("gitsigns.uv")
local uv = vim.loop

local M = {JobSpec = {}, }










M.job_cnt = 0

--- @param ... uv_pipe_t
local function try_close(...)
   for i = 1, select('#', ...) do
      local pipe = select(i, ...)
      if pipe and not pipe:is_closing() then
         pipe:close()
      end
   end
end

--- @param pipe uv_pipe_t
--- @param x string[]|string
local function handle_writer(pipe, x)
   if type(x) == "table" then
      for i, v in ipairs(x) do
         pipe:write(v)
         if i ~= #(x) then
            pipe:write("\n")
         else
            pipe:write("\n", function()
               try_close(pipe)
            end)
         end
      end
   elseif x then
      -- write is string
      pipe:write(x, function()
         try_close(pipe)
      end)
   end
end

--- @param pipe uv_pipe_t
--- @param output string[]
local function handle_reader(pipe, output)
   pipe:read_start(function(err, data)
      if err then
         log.eprint(err)
      end
      if data then
         output[#output + 1] = data
      else
         try_close(pipe)
      end
   end)
end

--- @param obj table
--- @param callback fun(_: integer, _: integer, _: string?, _: string?)
function M.run_job(obj, callback)
   local __FUNC__ = 'run_job'
   if log.debug_mode then
      local cmd = obj.command .. ' ' .. table.concat(obj.args, ' ')
      log.dprint(cmd)
   end

   local stdout_data = {}
   local stderr_data = {}

   local stdout = guv.new_pipe(false)
   local stderr = guv.new_pipe(false)
   local stdin
   if obj.writer then
      stdin = guv.new_pipe(false)
   end

   --- @type uv_process_t?, integer|string
   local handle, _pid
   handle, _pid = vim.loop.spawn(obj.command, {
      args = obj.args,
      stdio = { stdin, stdout, stderr },
      cwd = obj.cwd,
   },
   function(code, signal)
      if handle then
         handle:close()
      end
      stdout:read_stop()
      stderr:read_stop()

      try_close(stdin, stdout, stderr)

      local stdout_result = #stdout_data > 0 and table.concat(stdout_data) or nil
      local stderr_result = #stderr_data > 0 and table.concat(stderr_data) or nil

      callback(code, signal, stdout_result, stderr_result)
   end)


   if not handle then
      try_close(stdin, stdout, stderr)
      error(debug.traceback("Failed to spawn process: " .. vim.inspect(obj)))
   end

   handle_reader(stdout, stdout_data)
   handle_reader(stderr, stderr_data)
   handle_writer(stdin, obj.writer)

   M.job_cnt = M.job_cnt + 1
end

return M
