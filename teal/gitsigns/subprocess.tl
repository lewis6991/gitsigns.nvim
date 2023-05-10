local log = require("gitsigns.debug.log")
local guv = require("gitsigns.uv")
local uv = vim.loop

local record M
  job_cnt: integer

  record JobSpec
    command: string
    args: {string}
    cwd: string
    writer: {string} | string
  end
end

M.job_cnt = 0

--- @param ... uv_pipe_t
local function try_close(...: uv.Pipe)
  for i = 1, select('#', ...) do
    local pipe = select(i, ...)
    if pipe and not pipe:is_closing() then
      pipe:close()
    end
  end
end

--- @param pipe uv_pipe_t
--- @param x string[]|string
local function handle_writer(pipe: uv.Pipe, x: {string} | string)
  if x is {string} then
    for i, v in ipairs(x) do
      pipe:write(v)
      if i ~= #(x as {string}) then
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
local function handle_reader(pipe: uv.Pipe, output: {string})
  pipe:read_start(function(err: string, data: string)
    if err then
      log.eprint(err)
    end
    if data then
      output[#output+1] = data
    else
      try_close(pipe)
    end
  end)
end

--- @param obj table
--- @param callback fun(_: integer, _: integer, _: string?, _: string?)
function M.run_job(obj: M.JobSpec, callback: function(integer, integer, string, string))
  local __FUNC__ = 'run_job'
  if log.debug_mode then
    local cmd: string = obj.command..' '..table.concat(obj.args, ' ')
    log.dprint(cmd)
  end

  local stdout_data: {string} = {}
  local stderr_data: {string} = {}

  local stdout = guv.new_pipe(false)
  local stderr = guv.new_pipe(false)
  local stdin: uv.Pipe
  if obj.writer then
    stdin = guv.new_pipe(false)
  end

  --- @type uv_process_t?, integer|string
  local handle, _pid: uv.Process, integer
  handle, _pid = vim.loop.spawn(obj.command, {
    args  = obj.args,
    stdio = { stdin, stdout, stderr },
    cwd   = obj.cwd
  },
    function(code: integer, signal: integer)
      if handle then
        handle:close()
      end
      stdout:read_stop()
      stderr:read_stop()

      try_close(stdin, stdout, stderr)

      local stdout_result = #stdout_data > 0 and table.concat(stdout_data) or nil
      local stderr_result = #stderr_data > 0 and table.concat(stderr_data) or nil

      callback(code, signal, stdout_result, stderr_result)
    end
  )

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
