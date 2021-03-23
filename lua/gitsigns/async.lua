





































 cb_function = {}
 async_function = {}

local co = coroutine

local M = {}

function M.async(func)
   return function(...)
      local params = { ... }
      return function(callback)
         local thread = co.create(func)
         local function step(...)
            local stat, ret = co.resume(thread, ...)
            assert(stat, ret)
            if co.status(thread) == "dead" then
               if callback then
                  callback(ret)
               end
            else
               (ret)(step)
            end
         end
         step(unpack(params))
      end
   end
end


function M.sync(func)
   return function(...)
      M.async(func)(...)()
   end
end


function M.arun(func)
   return function(...)
      func(...)()
   end
end

function M.awrap(func)
   return function(...)
      local params = { ... }
      return function(step)
         table.insert(params, step)
         return func(unpack(params))
      end
   end
end

function M.await(defer, ...)
   return co.yield(defer(...))
end

function M.await_main()
   if vim.in_fast_event() then
      co.yield(vim.schedule)
   end
end

return M
