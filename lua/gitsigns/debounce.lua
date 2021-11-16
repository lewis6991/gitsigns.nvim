local M = {}






function M.debounce_trailing(ms, fn)
   local timer = vim.loop.new_timer()
   return function(...)
      local argv = { ... }
      timer:start(ms, 0, function()
         timer:stop()
         fn(unpack(argv))
      end)
   end
end







function M.throttle_leading(ms, fn)
   local timer = vim.loop.new_timer()
   local running = false
   return function(...)
      if not running then
         timer:start(ms, 0, function()
            running = false
            timer:stop()
         end)
         running = true
         fn(...)
      end
   end
end















function M.throttle_by_id(fn)
   local scheduled = {}
   local running = {}
   return function(id, ...)
      if scheduled[id] then

         return
      end
      scheduled[id] = true
      if running[id] then
         return
      end
      while scheduled[id] do
         scheduled[id] = nil
         running[id] = true
         fn(id, ...)
         running[id] = nil
      end
   end
end

return M
