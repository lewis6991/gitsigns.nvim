





















local M = {}



local function wrap(func, argc, protected)
   assert(argc)
   return function(...)
      if not coroutine.running() then
         return func(...)
      end
      return coroutine.yield(func, argc, protected, ...)
   end
end





function M.wrap(func, argc)
   return wrap(func, argc, false)
end





function M.pwrap(func, argc)
   return wrap(func, argc, true)
end





function M.void(func)
   return function(...)
      if coroutine.running() then
         return func(...)
      end

      local co = coroutine.create(func)

      local function step(...)
         local ret = { coroutine.resume(co, ...) }
         local stat, err_or_fn, nargs, protected = unpack(ret)

         if not stat then
            error(string.format("The coroutine failed with this message: %s\n%s",
            err_or_fn, debug.traceback(co)))
         end

         if coroutine.status(co) == 'dead' then
            return
         end

         assert(type(err_or_fn) == "function", "type error :: expected func")

         local args = { select(5, unpack(ret)) }
         if protected then
            args[nargs] = function(...)
               (step)(true, ...)
            end
            local ok, err = pcall(err_or_fn, unpack(args, 1, nargs))

            if not ok then
               (step)(ok, err)
            end
         else
            args[nargs] = step
            err_or_fn(unpack(args, 1, nargs))
         end
      end

      step(...)
   end
end



M.scheduler = M.wrap(vim.schedule, 1)

return M
