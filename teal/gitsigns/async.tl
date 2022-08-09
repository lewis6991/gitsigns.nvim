local co = coroutine

local record Async
  -- Order by highest number of return types

  void: function       (function()     ): function()
  void: function<A1>   (function(A1)   ): function(A1)
  void: function<A1,A2>(function(A1,A2)): function(A1,A2)
  void: function<A1,A2,A3,A4,R1>(function(A1,A2,A3,A4): R1): function(A1,A2,A3,A4): R1
  void: function<A1,A2,A3,A4>(function(A1,A2,A3,A4)): function(A1,A2,A3,A4)

  wrap: function<A1,A2,R1,R2>   (function(A1,A2,      function(R1,R2)), integer): function(A1,A2): R1,R2
  wrap: function<A1,A2,A3,A4,R1>(function(A1,A2,A3,A4,function(R1)   ), integer): function(A1,A2,A3,A4): R1
  wrap: function<A1,A2,A3>      (function(A1,A2,A3,   function())     , integer): function(A1,A2,A3)

  scheduler: function()
end


local async_thread = {
  threads: {string:boolean} = {}
}

local function threadtostring(x: thread): string
  if jit then
    return string.format('%p', x)
  else
    return tostring(x):match('thread: (.*)')
  end
end

-- Are we currently running inside an async thread
function async_thread.running(): boolean
  local thread = co.running()
  local id = threadtostring(thread)
  return async_thread.threads[id]
end

-- Create an async thread
function async_thread.create(fn: function): thread
  local thread = co.create(fn)
  local id = threadtostring(thread)
  async_thread.threads[id] = true
  return thread
end

-- Is the async thread finished
function async_thread.finished(x: thread): boolean
  if co.status(x) == 'dead' then
    local id = threadtostring(x)
    async_thread.threads[id] = nil
    return true
  end
  return false
end

---Executes a future with a callback when it is done
---@param async_fn Future: the future to execute
local function execute(async_fn: function, ...)
  local thread = async_thread.create(async_fn)

  local function step(...)
    local ret = {co.resume(thread, ...)} as {any}
    local stat, err_or_fn, nargs = unpack(ret) as (boolean, string|function, integer)

    if not stat then
      error(string.format("The coroutine failed with this message: %s\n%s",
        err_or_fn, debug.traceback(thread)))
    end

    if async_thread.finished(thread) then
      return
    end

    assert(err_or_fn is function, "type error :: expected func")

    local ret_fn = err_or_fn as function
    local args = {select(4, unpack(ret))}
    args[nargs] = step
    ret_fn(unpack(args, 1, nargs))
  end

  step(...)
end

local record M
  scheduler: function()
end

---Creates an async function with a callback style function.
---@param func function: A callback style function to be converted. The last argument must be the callback.
---@param argc number: The number of arguments of func. Must be included.
---@return function: Returns an async function
function M.wrap(func: function, argc: integer): function
  assert(argc)
  return function(...): any...
    if not async_thread.running() then
      -- print(debug.traceback('Warning: calling async function in non-async context', 2))
      return func(...)
    end
    return co.yield(func, argc, ...)
  end
end

---Use this to create a function which executes in an async context but
---called from a non-async context. Inherently this cannot return anything
---since it is non-blocking
---@param func function
function M.void(func: function): function
  return function(...): any
    if async_thread.running() then
      -- print(debug.traceback('Warning: calling void function in async context', 2))
      return func(...)
    end
    execute(func, ...)
  end
end

---An async function that when called will yield to the Neovim scheduler to be
---able to call the API.
M.scheduler = M.wrap(vim.schedule, 1) as function()

return M as Async
