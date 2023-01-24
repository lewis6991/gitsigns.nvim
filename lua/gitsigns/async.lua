





















local M = {}



local Async_T = {}
























local handles = setmetatable({}, { __mode = 'k' })


function M.running()
   local current = coroutine.running()
   if current and handles[current] then
      return true
   end
end


local function maxn(x)
   return ((table).maxn)(x)
end

local function is_Async_T(handle)
   if handle and
      type(handle) == 'table' and
      vim.is_callable(handle.cancel) and
      vim.is_callable(handle.is_cancelled) then
      return true
   end
end


function Async_T:cancel(cb)

   if self._current and not self._current:is_cancelled() then
      self._current:cancel(cb)
   end
end

function Async_T.new(co)
   local handle = setmetatable({}, { __index = Async_T })
   handles[co] = handle
   return handle
end


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
         local err = ret[2]
         error(string.format("The coroutine failed with this message: %s\n%s",
         err, debug.traceback(co)))
      end

      if coroutine.status(co) == 'dead' then
         if callback then
            callback(unpack(ret, 4, maxn(ret)))
         end
         return
      end

      local _, nargs, fn = unpack(ret)

      assert(type(fn) == 'function', "type error :: expected func")

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


   local function pfunc(...)
      local args = { ... }
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
      error(string.format("Wrapped function failed: %s\n%s", err, traceback))
   end

   return unpack(ret, 2, maxn(ret))
end





function M.wrap(func, argc)
   assert(argc)
   return function(...)
      if not M.running() then
         return func(...)
      end
      return M.wait(argc, func, ...)
   end
end





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





function M.void(func)
   return function(...)
      if M.running() then
         return func(...)
      end
      return run(func, nil, ...)
   end
end



M.scheduler = M.wrap(vim.schedule, 1)

return M
