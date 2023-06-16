-- Order by highest number of return types

local M = {}

local Async_T = {}

-- Handle for an object currently running on the event loop.
-- The coroutine is paused while this is active.
-- Must provide methods cancel() and is_cancelled()
--
-- Handle gets updated on each call to a wrapped functions, so provide access
-- to it via a proxy

-- Coroutine.running() was changed between Lua 5.1 and 5.2:
-- - 5.1: Returns the running coroutine, or nil when called by the main thread.
-- - 5.2: Returns the running coroutine plus a boolean, true when the running
--    coroutine is the main one.
--
-- For LuaJIT, 5.2 behaviour is enabled with LUAJIT_ENABLE_LUA52COMPAT
--
-- We need to handle both.

-- Store all the async threads in a weak table so we don't prevent them from
-- being garbage collected
--- @type table<thread,uv_handle_t>
local handles = setmetatable({}, { __mode = 'k' })

--- Returns whether the current execution context is async.
function M.running()
  local current = coroutine.running()
  if current and handles[current] then
    return true
  end
end

local function is_Async_T(handle)
  if
    handle
    and type(handle) == 'table'
    and vim.is_callable(handle.cancel)
    and vim.is_callable(handle.is_cancelled)
  then
    return true
  end
end

-- Analogous to uv.close
function Async_T:cancel(cb)
  -- Cancel anything running on the event loop
  if self._current and not self._current:is_cancelled() then
    self._current:cancel(cb)
  end
end

function Async_T.new(co)
  local handle = setmetatable({}, { __index = Async_T })
  handles[co] = handle
  return handle
end

-- Analogous to uv.is_closing
function Async_T:is_cancelled()
  return self._current and self._current:is_cancelled()
end

local function run(func, callback, ...)
  local co = coroutine.create(func)
  local handle = Async_T.new(co)

  local function step(...)
    local ret = { coroutine.resume(co, ...) }
    local stat = ret[1]

    if not stat then
      local err = ret[2] --[[@as string]]
      error(
        string.format('The coroutine failed with this message: %s\n%s', err, debug.traceback(co))
      )
    end

    if coroutine.status(co) == 'dead' then
      if callback then
        callback(unpack(ret, 4, table.maxn(ret)))
      end
      return
    end

    --- @type integer, function
    local nargs, fn = ret[2], ret[3]

    assert(type(fn) == 'function', 'type error :: expected func')

    local args = { select(4, unpack(ret)) }
    args[nargs] = step

    local r = fn(unpack(args, 1, nargs))
    if is_Async_T(r) then
      handle._current = r
    end
  end

  step(...)
  return handle
end

function M.wait(argc, func, ...)
  -- Always run the wrapped functions in xpcall and re-raise the error in the
  -- coroutine. This makes pcall work as normal.
  local function pfunc(...)
    local args = { ... } --- @type any[]
    local cb = args[argc]
    args[argc] = function(...)
      cb(true, ...)
    end
    xpcall(func, function(err)
      cb(false, err, debug.traceback())
    end, unpack(args, 1, argc))
  end

  local ret = { coroutine.yield(argc, pfunc, ...) }

  local ok = ret[1]
  if not ok then
    local _, err, traceback = unpack(ret)
    error(string.format('Wrapped function failed: %s\n%s', err, traceback))
  end

  return unpack(ret, 2, table.maxn(ret))
end

---Creates an async function with a callback style function.
---@param func function: A callback style function to be converted. The last argument must be the callback.
---@param argc number: The number of arguments of func. Must be included.
---@return function: Returns an async function
function M.wrap(func, argc)
  assert(argc)
  return function(...)
    if not M.running() then
      return func(...)
    end
    return M.wait(argc, func, ...)
  end
end

---Use this to create a function which executes in an async context but
---called from a non-async context. Inherently this cannot return anything
---since it is non-blocking
---@generic F: function
---@param func F
---@return F
function M.create(func, argc)
  argc = argc or 0
  return function(...)
    if M.running() then
      return func(...)
    end
    local callback = select(argc + 1, ...)
    return run(func, callback, unpack({ ... }, 1, argc))
  end
end

---Use this to create a function which executes in an async context but
---called from a non-async context. Inherently this cannot return anything
---since it is non-blocking
---@param func async fun(...)
function M.void(func)
  return function(...)
    if M.running() then
      return func(...)
    end
    return run(func, nil, ...)
  end
end

---An async function that when called will yield to the Neovim scheduler to be
---able to call the API.
M.scheduler = M.wrap(vim.schedule, 1)

return M
