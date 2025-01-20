local M = {}

--- @class Gitsigns.AsyncTask
--- @field _current Gitsigns.AsyncTask
local Task = {}

-- Handle for an object currently running on the event loop.
-- The coroutine is paused while this is active.
-- Must provide methods close() and is_closing()
--
-- Handle gets updated on each call to a wrapped functions, so provide access
-- to it via a proxy

--- Store all the async threads in a weak table so we don't prevent them from
--- being garbage collected
--- @type table<thread,Gitsigns.AsyncTask>
local handles = setmetatable({}, { __mode = 'k' })

--- Returns whether the current execution context is async.
local function running()
  local current = coroutine.running()
  return current and handles[current] ~= nil
end

--- @param handle any
--- @return boolean
local function is_Async_T(handle)
  return handle
    and type(handle) == 'table'
    and vim.is_callable(handle.close)
    and vim.is_callable(handle.is_closing)
end

--- Analogous to uv.close
--- @param cb function
function Task:close(cb)
  -- Close anything running on the event loop
  if self._current and not self._current:is_closing() then
    self._current:close(cb)
  end
end

--- @param co thread
--- @return Gitsigns.AsyncTask
function Task.new(co)
  local handle = setmetatable({}, { __index = Task })
  handles[co] = handle
  return handle
end

--- Analogous to uv.is_closing
--- @return boolean
function Task:is_closing()
  return self._current and self._current:is_closing()
end

--- @param func function
--- @param callback? fun(...: any)
--- @param ... any
--- @return Gitsigns.AsyncTask
local function run(func, callback, ...)
  local co = coroutine.create(func)
  local handle = Task.new(co)

  local function step(...)
    local ret = { coroutine.resume(co, ...) }
    local stat = ret[1]

    if not stat then
      local co_err = ret[2] --- @type string
      error(debug.traceback(co, string.format('The async coroutine failed: %s', co_err)))
    elseif coroutine.status(co) == 'dead' then
      if callback then
        callback(unpack(ret, 2, table.maxn(ret)))
      end
    else
      --- @type fun(...: any): any
      local fn = ret[2]

      assert(type(fn) == 'function', 'type error :: expected func')

      local r = fn(step)
      if is_Async_T(r) then
        --- @cast r Gitsigns.AsyncTask
        handle._current = r
      end
    end
  end

  step(...)
  return handle
end

--- Must be called from an async context.
--- @param argc integer
--- @param func function
--- @param ... any
--- @return any ...
function M.await(argc, func, ...)
  assert(running(), 'Not in an async context')
  local args, nargs = { ... }, select('#', ...)

  -- Always run the wrapped functions in xpcall and re-raise the error in the
  -- coroutine. This makes pcall work as normal.
  local stat, ret = coroutine.yield(function(callback)
    args[argc] = function(...)
      callback(true, { ... })
    end
    nargs = math.max(nargs, argc)
    xpcall(func, function(err)
      callback(false, { err, debug.traceback() })
    end, unpack(args, 1, nargs))
  end)

  if not stat then
    --- @type string, string
    local err, traceback = ret[1], ret[2]
    error(string.format('Wrapped function failed: %s\n%s', err, traceback))
  end

  return unpack(ret, 1, table.maxn(ret))
end

--- @param argc integer
--- @param func function
--- @param ... any
--- @return any ...
function M.wait_sync(argc, func, ...)
  local nargs, args = select('#', ...), { ... }
  local done = false
  local ret = nil

  args[argc] = function(...)
    ret = { ... }
    done = true
  end
  nargs = math.max(nargs, argc)

  func(unpack(args, 1, nargs))

  vim.wait(10000, function()
    return done
  end)

  if not done then
    error('Timeout waiting for async function')
  end

  assert(ret)
  return unpack(ret, 1, table.maxn(ret))
end

--- Creates an async function with a callback style function.
--- @param argc number The number of arguments of func. Must be included.
--- @param func function A callback style function to be converted. The last argument must be the callback.
--- @return function: Returns an async function
function M.awrap(argc, func)
  assert(type(func) == 'function')
  assert(type(argc) == 'number')
  return function(...)
    return M.await(argc, func, ...)
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

  --- @param ... any
  --- @return any ...
  return function(...)
    local callback = argc and select(argc + 1, ...) or nil
    assert(not callback or type(callback) == 'function')
    return run(func, callback, unpack({ ... }, 1, argc))
  end
end

--- An async function that when called will yield to the Neovim scheduler to be
--- able to call the API.
M.scheduler = M.awrap(1, vim.schedule)

function M.run(func, ...)
  return run(func, nil, ...)
end

return M
