local co = coroutine


















local async_thread = {
   threads = {},
}

local function threadtostring(x)
   if jit then
      return string.format('%p', x)
   else
      return tostring(x):match('thread: (.*)')
   end
end


function async_thread.running()
   local thread = co.running()
   local id = threadtostring(thread)
   return async_thread.threads[id]
end


function async_thread.create(fn)
   local thread = co.create(fn)
   local id = threadtostring(thread)
   async_thread.threads[id] = true
   return thread
end


function async_thread.finished(x)
   if co.status(x) == 'dead' then
      local id = threadtostring(x)
      async_thread.threads[id] = nil
      return true
   end
   return false
end



local function execute(async_fn, ...)
   local thread = async_thread.create(async_fn)

   local function step(...)
      local ret = { co.resume(thread, ...) }
      local stat, err_or_fn, nargs = unpack(ret)

      if not stat then
         error(string.format("The coroutine failed with this message: %s\n%s",
         err_or_fn, debug.traceback(thread)))
      end

      if async_thread.finished(thread) then
         return
      end

      assert(type(err_or_fn) == "function", "type error :: expected func")

      local ret_fn = err_or_fn
      local args = { select(4, unpack(ret)) }
      args[nargs] = step
      ret_fn(unpack(args, 1, nargs))
   end

   step(...)
end

local M = {}







function M.wrap(func, argc)
   assert(argc)
   return function(...)
      if not async_thread.running() then

         return func(...)
      end
      return co.yield(func, argc, ...)
   end
end





function M.void(func)
   return function(...)
      if async_thread.running() then

         return func(...)
      end
      execute(func, ...)
   end
end



M.scheduler = M.wrap(vim.schedule, 1)

return M
