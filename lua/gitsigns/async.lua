

















local M = {}











local main_co_or_nil = coroutine.running()





function M.wrap(func, argc)
   assert(argc)
   return function(...)
      if coroutine.running() == main_co_or_nil then
         return func(...)
      end
      return coroutine.yield(func, argc, ...)
   end
end





function M.void(func)
   return function(...)
      if coroutine.running() ~= main_co_or_nil then
         return func(...)
      end

      local co = coroutine.create(func)

      local function step(...)
         local ret = { coroutine.resume(co, ...) }
         local stat, err_or_fn, nargs = unpack(ret)

         if not stat then
            error(string.format("The coroutine failed with this message: %s\n%s",
            err_or_fn, debug.traceback(co)))
         end

         if coroutine.status(co) == 'dead' then
            return
         end

         assert(type(err_or_fn) == "function", "type error :: expected func")

         local args = { select(4, unpack(ret)) }
         args[nargs] = step
         err_or_fn(unpack(args, 1, nargs))
      end

      step(...)
   end
end



M.scheduler = M.wrap(vim.schedule, 1)

return M
