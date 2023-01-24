local record Async
  -- Order by highest number of return types

  create: function<T>(T, integer): T

  void: function<F>(F): F

  wrap: function<A1,R1,R2,R3,R4>   (function(A1,            function(R1,R2,R3,R4)), integer): function(A1            ): R1,R2,R3,R4
  wrap: function<A1,A2,R1,R2>      (function(A1,A2,         function(R1,R2)      ), integer): function(A1,A2         ): R1,R2
  wrap: function<A1,A2,A3,A4,R1>   (function(A1,A2,A3,A4,   function(R1)         ), integer): function(A1,A2,A3,A4   ): R1
  wrap: function<A1,A2,A3,A4,A5,R1>(function(A1,A2,A3,A4,A5,function(R1)         ), integer): function(A1,A2,A3,A4,A5): R1
  wrap: function<A1,A2,A3>         (function(A1,A2,A3,      function()           ), integer): function(A1,A2,A3)

  wait: function<A1,R1,R2,R3,R4>   (integer, function(A1,            function(R1,R2,R3,R4)), A1                ): R1,R2,R3,R4
  wait: function<A1,A2,R1,R2>      (integer, function(A1,A2,         function(R1,R2)      ), A1, A2            ): R1,R2
  wait: function<A1,A2,A3,A4,R1>   (integer, function(A1,A2,A3,A4,   function(R1)         ), A1, A2, A3, A4    ): R1
  wait: function<A1,A2,A3,A4,A5,R1>(integer, function(A1,A2,A3,A4,A5,function(R1)         ), A1, A2, A3, A4, A5): R1
  wait: function<A1,A2,A3>         (integer, function(A1,A2,A3,      function()           ), A1, A2, A3)

  scheduler: function()
end

local record M
  scheduler: function()
end

local record Async_T

  -- Handle for an object currently running on the event loop.
  -- The coroutine is paused while this is active.
  -- Must provide methods cancel() and is_cancelled()
  --
  -- Handle gets updated on each call to a wrapped functions, so provide access
  -- to it via a proxy
  _current: Async_T

  cancel: function(Async_T, function)
  is_cancelled: function(Async_T): boolean
end

-- Coroutine.running() was changed between Lua 5.1 and 5.2:
-- - 5.1: Returns the running coroutine, or nil when called by the main thread.
-- - 5.2: Returns the running coroutine plus a boolean, true when the running
--   coroutine is the main one.
--
-- For LuaJIT, 5.2 behaviour is enabled with LUAJIT_ENABLE_LUA52COMPAT
--
-- We need to handle both.

-- Store all the async threads in a weak table so we don't prevent them from
-- being garbage collected
local handles = setmetatable({} as {thread:Async_T}, { __mode = 'k' })

--- Returns whether the current execution context is async.
function M.running(): boolean
  local current = coroutine.running()
  if current and handles[current] then
    return true
  end
end

-- hack: teal doesn't know table.maxn exists
local function maxn(x: table): integer
  return ((table as table).maxn as function)(x) as integer
end

local function is_Async_T(handle: Async_T): boolean
  if handle
    and type(handle) == 'table'
    and vim.is_callable(handle.cancel)
    and vim.is_callable(handle.is_cancelled) then
    return true
  end
end

-- Analogous to uv.close
function Async_T:cancel(cb: function)
  -- Cancel anything running on the event loop
  if self._current and not self._current:is_cancelled() then
    self._current:cancel(cb)
  end
end

function Async_T.new(co: thread): Async_T
  local handle = setmetatable({} as Async_T, { __index = Async_T })
  handles[co] = handle
  return handle
end

-- Analogous to uv.is_closing
function Async_T:is_cancelled(): boolean
  return self._current and self._current:is_cancelled()
end

local function run(func: function, callback: function, ...: any): Async_T
  local co = coroutine.create(func)
  local handle = Async_T.new(co)

  local function step(...: any)
    local ret = {coroutine.resume(co, ...)}
    local stat = ret[1] as boolean

    if not stat then
      local err = ret[2] as string
      error(string.format("The coroutine failed with this message: %s\n%s",
        err, debug.traceback(co)))
    end

    if coroutine.status(co) == 'dead' then
      if callback then
        callback(unpack(ret, 4, maxn(ret)))
      end
      return
    end

    local _, nargs, fn = unpack(ret) as (any, integer, function(...:any): Async_T)

    assert(type(fn) == 'function', "type error :: expected func")

    local args = {select(4, unpack(ret))}
    args[nargs] = step

    local r = fn(unpack(args, 1, nargs))
    if is_Async_T(r) then
      handle._current = r
    end
  end

  step(...)
  return handle
end

function M.wait(argc: integer, func: function, ...): any...
  -- Always run the wrapped functions in xpcall and re-raise the error in the
  -- coroutine. This makes pcall work as normal.
  local function pfunc(...: any)
    local args = { ... }
    local cb = args[argc] as function
    args[argc] = function(...: any)
      cb(true, ...)
    end
    xpcall(func, function(err)
      cb(false, err, debug.traceback())
    end, unpack(args, 1, argc))
  end

  local ret = {coroutine.yield(argc, pfunc, ...)}

  local ok = ret[1]
  if not ok then
    local _, err, traceback = unpack(ret)
    error(string.format("Wrapped function failed: %s\n%s", err, traceback))
  end

  return unpack(ret, 2, maxn(ret))
end

---Creates an async function with a callback style function.
---@param func function: A callback style function to be converted. The last argument must be the callback.
---@param argc number: The number of arguments of func. Must be included.
---@return function: Returns an async function
function M.wrap(func: function, argc: integer): function
  assert(argc)
  return function(...): any...
    if not M.running() then
      return func(...)
    end
    return M.wait(argc, func, ...)
  end
end

---Use this to create a function which executes in an async context but
---called from a non-async context. Inherently this cannot return anything
---since it is non-blocking
---@param func function
function M.create(func: function, argc: integer): function(...: any): Async_T
  argc = argc or 0
  return function(...: any): Async_T
    if M.running() then
      return func(...) as Async_T
    end
    local callback = select(argc+1, ...) as function
    return run(func, callback, unpack({...}, 1, argc))
  end
end

---Use this to create a function which executes in an async context but
---called from a non-async context. Inherently this cannot return anything
---since it is non-blocking
---@param func function
function M.void(func: function(...:any)): function(...:any): Async_T
  return function(...: any): Async_T
    if M.running() then
      return func(...)
    end
    return run(func, nil, ...)
  end
end

---An async function that when called will yield to the Neovim scheduler to be
---able to call the API.
M.scheduler = M.wrap(vim.schedule, 1) as function()

return M as Async
