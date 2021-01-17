

local co = coroutine

local M = {}

function M.async(name, func)
   assert(type(func) == "function", "type error :: expected func")
   local nparams = debug.getinfo(func, 'u').nparams


   return function(...)
      local params = { ... }
      local callback = params[nparams + 1]

      assert(type(callback) == "function" or callback == nil, "type error :: expected func, got " .. type(callback))

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
      step(unpack(params, 1, nparams))
   end
end

function M.async0(name, fn)
   return function()
      M.async(name, fn)()
   end
end


function M.awrap(func)
   assert(type(func) == "function", "type error :: expected func")
   return function(...)
      local params = { ... }
      return function(step)
         table.insert(params, step)
         return func(unpack(params))
      end
   end
end


function M.await(defer, ...)
   return co.yield(M.awrap(defer)(...))
end

function M.await_main()
   return M.await(vim.schedule)
end

return M
