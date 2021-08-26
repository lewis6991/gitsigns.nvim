local gsd = require("gitsigns.debug")
local uv = vim.loop

local record M
  path_sep: string
  is_unix: boolean
  job_cnt: integer

  record JobSpec
    command: string
    args: {string}
    cwd: string
    env: {string}
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

function M.path_exists(path: string): boolean
  return uv.fs_stat(path) and true or false
end

function M.run_job(obj: M.JobSpec, callback: function(integer, integer, {string}, {string})): M.JobSpec
  if gsd.debug_mode then
    local cmd: string = obj.command..' '..table.concat(obj.args, ' ')
    gsd.dprint(cmd)
  end

  if obj.env then
    local transform: {string} = {}
    for k, v in pairs(obj.env as {integer:string}) do
      if type(k) == "number" then
        table.insert(transform, v)
      elseif type(k) == "string" then
        table.insert(transform, k .. "=" .. tostring(v))
      end
    end
    obj.env = transform
  end

  obj._state = {}
  local s = obj._state
  s.stdout_data = {}
  s.stderr_data = {}

  s.stdout = uv.new_pipe(false)
  s.stderr = uv.new_pipe(false)

  s.handle, s.pid = uv.spawn(obj.command, {
    args  = obj.args,
    stdio = { s.stdin, s.stdout, s.stderr },
    cwd   = obj.cwd,
    env   = obj.env
  },
    function(code: integer, signal: integer)
      s.code = code
      s.signal = signal

      if s.stdout then s.stdout:read_stop() end
      if s.stderr then s.stderr:read_stop() end

      for _, handle in ipairs {s.stdin, s.stderr, s.stdout} do
        if handle and not handle:is_closing() then
          handle:close()
        end
      end

      local stdout_result = s.stdout_data and vim.split(table.concat(s.stdout_data), '\n')
      local stderr_result = s.stderr_data and vim.split(table.concat(s.stderr_data), '\n')

      callback(code, signal, stdout_result, stderr_result)
    end
  )

  if not s.handle then
    error(debug.traceback("Failed to spawn process: " .. vim.inspect(obj)))
  end

  s.stdout:read_start(function(_, data: string)
    if not s.stdout_data then
      s.stdout_data = {}
    end
    s.stdout_data[#s.stdout_data+1] = data
  end)

  s.stderr:read_start(function(_, data: string)
    if not s.stderr_data then
      s.stderr_data = {}
    end
    s.stderr_data[#s.stderr_data+1] = data
  end)

  if type(obj.writer) == "table" and vim.tbl_islist(obj.writer as table) then
    local writer_table = obj.writer as {string}
    local writer_len = #writer_table
    for i, v in ipairs(writer_table) do
      s.stdin:write(v)
      if i ~= writer_len then
        s.stdin:write "\n"
      else
        s.stdin:write("\n", function()
          s.stdin:close()
        end)
      end
    end
  elseif type(obj.writer) == "string" then
    s.stdin:write(obj.writer as string, function()
      s.stdin:close()
    end)
  end

  return obj
end

function M.get_jit_os(): string
  if jit then
    return jit.os:lower()
  end
  return
end

local jit_os: string

if jit then
  jit_os = jit.os:lower()
end

M.is_unix = (function(): boolean
  if jit_os == 'linux' or jit_os == 'osx' or jit_os == 'bsd' then
    return true
  end
  return false
end)()

function M.dirname(file: string): string
  return file:match(string.format('^(.+)%s[^%s]+', M.path_sep, M.path_sep))
end

function M.file_lines(file: string): {string}
  local text: {string} = {}
  for line in io.lines(file) do
    text[#text+1] = line
  end
  return text
end

M.path_sep = (function(): string
  if jit_os then
    if M.is_unix then
      return '/'
    end
    return '\\'
  end
  return package.config:sub(1, 1)
end)()

function M.tmpname(): string
  if M.is_unix then
    return os.tmpname()
  end
  return vim.fn.tempname()
end

function M.get_relative_time(timestamp: number): string
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

  local to_relative_string = function(time: number, divisor: number, time_word: string): string
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
