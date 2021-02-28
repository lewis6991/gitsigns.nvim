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

return M
