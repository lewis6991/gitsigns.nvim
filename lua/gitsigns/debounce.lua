local uv = require('gitsigns.uv')

local M = {}











function M.debounce_trailing(ms, fn)
   local timer = uv.new_timer(true)
   return function(...)
      local argv = { ... }
      timer:start(ms, 0, function()
         timer:stop()
         fn(unpack(argv))
      end)
   end
end







function M.throttle_leading(ms, fn)
   local timer = uv.new_timer(true)
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















function M.throttle_by_id(fn, schedule)
   local scheduled = {}
   local running = {}
   return function(id, ...)
      if scheduled[id] then

         return
      end
      if not running[id] or schedule then
         scheduled[id] = true
      end
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
