local uv = vim.loop

--- @class ProcessStream
--- @field _proc uv.uv_process_t
--- @field _pid integer
--- @field _child_stdin uv.uv_pipe_t
--- @field _child_stdout uv.uv_pipe_t
--- @field _exiting boolean
--- @field signal integer
--- @field status integer
local ProcessStream = {}

--- @param argv string[]
--- @return ProcessStream
function ProcessStream.spawn(argv)
  --- @type ProcessStream
  local self = setmetatable({
    _child_stdin = uv.new_pipe(false),
    _child_stdout = uv.new_pipe(false),
    _exiting = false,
  }, { __index = ProcessStream })

  local prog, args = argv[1], vim.list_slice(argv, 2)

  --- @diagnostic disable-next-line:missing-fields
  self._proc, self._pid = uv.spawn(prog, {
    stdio = { self._child_stdin, self._child_stdout, 2 },
    args = args,
  }, function(status, signal)
    self.status = status
    self.signal = signal
  end)

  if not self._proc then
    local err = self._pid
    error(err)
  end

  return self
end

function ProcessStream:write(data)
  self._child_stdin:write(data)
end

function ProcessStream:read_start(cb)
  self._child_stdout:read_start(function(err, chunk)
    if err then
      error(err)
    end
    cb(chunk)
  end)
end

function ProcessStream:read_stop()
  self._child_stdout:read_stop()
end

--- @param signal string
--- @return integer?
--- @return integer?
function ProcessStream:close(signal)
  if self._closed then
    return
  end
  self._closed = true
  self:read_stop()
  self._child_stdin:close()
  self._child_stdout:close()
  if type(signal) == 'string' then
    self._proc:kill('sig' .. signal)
  end
  while self.status == nil do
    uv.run('once')
  end
  return self.status, self.signal
end

return ProcessStream
