local gsd = require("gitsigns.debug")
local guv = require("gitsigns.uv")
local uv = vim.loop

local record M
  job_cnt: integer

  record JobSpec
    command: string
    args: {string}
    cwd: string
    writer: {string} | string

    record State
      handle: uv.Process
      pid: integer
      stdout_data: {string}
      stderr_data: {string}
      stdin: uv.Pipe
      stdout: uv.Pipe
      stderr: uv.Pipe
      code: integer
      signal: integer
    end
    _state: State
  end
end

M.job_cnt = 0

function M.run_job(obj: M.JobSpec, callback: function(integer, integer, string, string)): M.JobSpec
  if gsd.debug_mode then
    local cmd: string = obj.command..' '..table.concat(obj.args, ' ')
    gsd.dprint(cmd)
  end

  obj._state = {}
  local s = obj._state
  s.stdout_data = {}
  s.stderr_data = {}

  s.stdout = guv.new_pipe(false) as uv.Pipe
  s.stderr = guv.new_pipe(false) as uv.Pipe
  if obj.writer then
    s.stdin = guv.new_pipe(false) as uv.Pipe
  end

  s.handle, s.pid = guv.spawn(obj.command, {
    args  = obj.args,
    stdio = { s.stdin, s.stdout, s.stderr },
    cwd   = obj.cwd
  },
    function(code: integer, signal: integer)
      s.handle:close()
      s.code = code
      s.signal = signal

      if s.stdout then s.stdout:read_stop() end
      if s.stderr then s.stderr:read_stop() end

      if s.stdin  and not s.stdin:is_closing()  then s.stdin:close()  end
      if s.stdout and not s.stdout:is_closing() then s.stdout:close() end
      if s.stderr and not s.stderr:is_closing() then s.stderr:close() end

      local stdout_result = #s.stdout_data > 0 and table.concat(s.stdout_data) or nil
      local stderr_result = #s.stderr_data > 0 and table.concat(s.stderr_data) or nil

      callback(code, signal, stdout_result, stderr_result)
    end
  )

  if not s.handle then
    if s.stdin  and not s.stdin:is_closing()  then s.stdin:close()  end
    if s.stdout and not s.stdout:is_closing() then s.stdout:close() end
    if s.stderr and not s.stderr:is_closing() then s.stderr:close() end
    error(debug.traceback("Failed to spawn process: " .. vim.inspect(obj)))
  end

  s.stdout:read_start(function(_, data: string)
    s.stdout_data[#s.stdout_data+1] = data
  end)

  s.stderr:read_start(function(_, data: string)
    s.stderr_data[#s.stderr_data+1] = data
  end)

  local writer = obj.writer
  if writer is {string} then
    local writer_len = #writer
    for i, v in ipairs(writer) do
      s.stdin:write(v)
      if i ~= writer_len then
        s.stdin:write("\n")
      else
        s.stdin:write("\n", function()
          s.stdin:close()
        end)
      end
    end
  elseif writer then
    -- write is string
    s.stdin:write(writer, function()
      s.stdin:close()
    end)
  end

  M.job_cnt = M.job_cnt + 1
  return obj
end

return M
