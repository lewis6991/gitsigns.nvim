local record Async
  -- Order by highest number of return types

  void: function       (function()     ): function()
  void: function<A1>   (function(A1)   ): function(A1)
  void: function<A1,A2>(function(A1,A2)): function(A1,A2)
  void: function<A1,A2,A3,A4,R1>(function(A1,A2,A3,A4): R1): function(A1,A2,A3,A4): R1
  void: function<A1,A2,A3,A4,A5,R1>(function(A1,A2,A3,A4,A5): R1): function(A1,A2,A3,A4,A5): R1
  void: function<A1,A2,A3,A4>(function(A1,A2,A3,A4)): function(A1,A2,A3,A4)

  wrap: function<A1,A2,R1,R2>   (function(A1,A2,      function(R1,R2)), integer): function(A1,A2): R1,R2
  wrap: function<A1,A2,A3,A4,R1>(function(A1,A2,A3,A4,function(R1)   ), integer): function(A1,A2,A3,A4): R1
  wrap: function<A1,A2,A3,A4,A5,R1>(function(A1,A2,A3,A4,A5,function(R1)), integer): function(A1,A2,A3,A4,A5): R1
  wrap: function<A1,A2,A3>      (function(A1,A2,A3,   function())     , integer): function(A1,A2,A3)

  scheduler: function()
end

local record M
  scheduler: function()
end

-- Coroutine.running() was changed between Lua 5.1 and 5.2:
-- - 5.1: Returns the running coroutine, or nil when called by the main thread.
-- - 5.2: Returns the running coroutine plus a boolean, true when the running
--   coroutine is the main one.
--
-- For LuaJIT, 5.2 behaviour is enabled with LUAJIT_ENABLE_LUA52COMPAT
--
-- We need to handle both.
local main_co_or_nil = coroutine.running()

---Creates an async function with a callback style function.
---@param func function: A callback style function to be converted. The last argument must be the callback.
---@param argc number: The number of arguments of func. Must be included.
---@return function: Returns an async function
function M.wrap(func: function, argc: integer): function
  assert(argc)
  return function(...): any...
    if coroutine.running() == main_co_or_nil then
      return func(...)
    end
    return coroutine.yield(func, argc, ...)
  end
end

---Use this to create a function which executes in an async context but
---called from a non-async context. Inherently this cannot return anything
---since it is non-blocking
---@param func function
function M.void(func: function): function
  return function(...): any
    if coroutine.running() ~= main_co_or_nil then
      return func(...)
    end

    local co = coroutine.create(func)

    local function step(...)
      local ret = {coroutine.resume(co, ...)} as {any}
      local stat, err_or_fn, nargs = unpack(ret) as (boolean, function, integer)

      if not stat then
        error(string.format("The coroutine failed with this message: %s\n%s",
          err_or_fn, debug.traceback(co)))
      end

      if coroutine.status(co) == 'dead' then
        return
      end

      assert(err_or_fn is function, "type error :: expected func")

      local args = {select(4, unpack(ret))}
      args[nargs] = step
      err_or_fn(unpack(args, 1, nargs))
    end

    step(...)
  end
end

---An async function that when called will yield to the Neovim scheduler to be
---able to call the API.
M.scheduler = M.wrap(vim.schedule, 1) as function()

return M as Async
