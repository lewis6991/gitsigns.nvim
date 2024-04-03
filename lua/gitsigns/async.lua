local M = {}

--- @class Gitsigns.Async_T
--- @field _current Gitsigns.Async_T
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

--- Store all the async threads in a weak table so we don't prevent them from
--- being garbage collected
--- @type table<thread,Gitsigns.Async_T>
local handles = setmetatable({}, { __mode = 'k' })

--- Returns whether the current execution context is async.
function M.running()
  local current = coroutine.running()
  if current and handles[current] then
    return true
  end
  return false
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

--- Analogous to uv.close
--- @param cb function
function Async_T:cancel(cb)
  -- Cancel anything running on the event loop
  if self._current and not self._current:is_cancelled() then
    self._current:cancel(cb)
  end
end

--- @param co thread
--- @return Gitsigns.Async_T
function Async_T.new(co)
  local handle = setmetatable({}, { __index = Async_T })
  handles[co] = handle
  return handle
end

--- Analogous to uv.is_closing
--- @return boolean
function Async_T:is_cancelled()
  return self._current and self._current:is_cancelled()
end

--- @param func function
--- @param callback? fun(...: any)
--- @param ... any
--- @return Gitsigns.Async_T
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
        callback(unpack(ret, 2, table.maxn(ret)))
      end
      return
    end

    --- @type integer, fun(...: any): any
    local nargs, fn = ret[2], ret[3]

    assert(type(fn) == 'function', 'type error :: expected func')

    local args = { select(4, unpack(ret)) }
    args[nargs] = step

    local r = fn(unpack(args, 1, nargs))
    if is_Async_T(r) then
      --- @cast r Gitsigns.Async_T
      handle._current = r
    end
  end

  step(...)
  return handle
end

--- @param argc integer
--- @param func function
--- @param ... any
--- @return any ...
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
    --- @type string, string
    local err, traceback = ret[2], ret[3]
    error(string.format('Wrapped function failed: %s\n%s', err, traceback))
  end

  return unpack(ret, 2, table.maxn(ret))
end

--- Creates an async function with a callback style function.
--- @param argc number The number of arguments of func. Must be included.
--- @param func function A callback style function to be converted. The last argument must be the callback.
--- @return function: Returns an async function
function M.wrap(argc, func)
  assert(type(func) == 'function')
  assert(type(argc) == 'number')
  return function(...)
    return M.wait(argc, func, ...)
  end
end

--- create([argc, ] func)
---
--- Use this to create a function which executes in an async context but
--- called from a non-async context. Inherently this cannot return anything
--- since it is non-blocking
---
--- If argc is not provided, then the created async function cannot be continued
---
--- @generic F: function
--- @param argc_or_func F|integer
--- @param func? F
--- @return F
function M.create(argc_or_func, func)
  local argc --- @type integer
  if type(argc_or_func) == 'function' then
    assert(not func)
    func = argc_or_func
  elseif type(argc_or_func) == 'number' then
    assert(type(func) == 'function')
    argc = argc_or_func
  end

  --- @cast func function

  return function(...)
    local callback = argc and select(argc + 1, ...) or nil
    return run(func, callback, unpack({ ... }, 1, argc))
  end
end

--- An async function that when called will yield to the Neovim scheduler to be
--- able to call the API.
M.scheduler = M.wrap(1, vim.schedule)

function M.run(func, ...)
  return run(func, nil, ...)
end

return M
