local a = require('plenary/async_lib/async')

local M = {}
































































































M.void = a.void
M.void_async = function(func)
   return M.void(a.async(func))
end

M.await0 = a.await
M.await1 = a.await
M.await2 = a.await
M.await3 = a.await
M.await4 = a.await
M.await_main = function()
   a.await(a.scheduler())
end

M.wrap0 = function(func)
   return a.wrap(func, 1)
end
M.wrap0_1 = function(func)
   return a.wrap(func, 1)
end
M.wrap0_2 = function(func)
   return a.wrap(func, 1)
end
M.wrap0_3 = function(func)
   return a.wrap(func, 1)
end
M.wrap0_4 = function(func)
   return a.wrap(func, 1)
end
M.wrap1 = function(func)
   return a.wrap(func, 2)
end
M.wrap1_1 = function(func)
   return a.wrap(func, 2)
end
M.wrap1_2 = function(func)
   return a.wrap(func, 2)
end
M.wrap1_3 = function(func)
   return a.wrap(func, 2)
end
M.wrap1_4 = function(func)
   return a.wrap(func, 2)
end
M.wrap2 = function(func)
   return a.wrap(func, 3)
end
M.wrap2_1 = function(func)
   return a.wrap(func, 3)
end
M.wrap2_2 = function(func)
   return a.wrap(func, 3)
end
M.wrap2_3 = function(func)
   return a.wrap(func, 3)
end
M.wrap2_4 = function(func)
   return a.wrap(func, 3)
end
M.wrap3 = function(func)
   return a.wrap(func, 4)
end
M.wrap3_1 = function(func)
   return a.wrap(func, 4)
end
M.wrap3_2 = function(func)
   return a.wrap(func, 4)
end
M.wrap3_3 = function(func)
   return a.wrap(func, 4)
end
M.wrap3_4 = function(func)
   return a.wrap(func, 4)
end
M.wrap4 = function(func)
   return a.wrap(func, 5)
end
M.wrap4_1 = function(func)
   return a.wrap(func, 5)
end
M.wrap4_2 = function(func)
   return a.wrap(func, 5)
end
M.wrap4_3 = function(func)
   return a.wrap(func, 5)
end
M.wrap4_4 = function(func)
   return a.wrap(func, 5)
end

M.async0 = a.async
M.async0_1 = a.async
M.async0_2 = a.async
M.async0_3 = a.async
M.async0_4 = a.async
M.async1 = a.async
M.async1_1 = a.async
M.async1_2 = a.async
M.async1_3 = a.async
M.async1_4 = a.async
M.async2 = a.async
M.async2_1 = a.async
M.async2_2 = a.async
M.async2_3 = a.async
M.async2_4 = a.async
M.async3 = a.async
M.async3_1 = a.async
M.async3_2 = a.async
M.async3_3 = a.async
M.async3_4 = a.async
M.async4 = a.async
M.async4_1 = a.async
M.async4_2 = a.async
M.async4_3 = a.async
M.async4_4 = a.async

return M
