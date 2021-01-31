-- Originated from:
-- https://github.com/ms-jpq/neovim-async-tutorial/blob/neo/lua/async.lua
--
-- A raw async function has the signature:
--
--     function(arg1: <type1>, arg2: <type2>, ...) -> function(callback: function(<return type>))
--
-- Functions of this form can be asynchronously called using await():
--
--     local ret: <return type> = await(<func name>, arg1, arg2, ...)
--
-- To transform a regular function into one that can be called asynchronously it
-- must be wrapped in a call to async():
--
--     local <func name> = async(function(arg1, arg2, ...)
--         <body>
--     end)
--
-- Internally async() creates a lua thread which is started when the wrapped
-- function is called and returns a function with the structure of a raw async
-- function (a function that returns a function with a callback argument).
--
-- All asynchronous functions in libuv (vim.loop) have their callback as the
-- final argument. To convert these to functions that can be used with await()
-- they must be wrapped in a call to awrap(). For example, for timer_start()
-- which has the signature:
--
--     vim.loop.timer_start(timer, timeout, repeat, callback)
--
-- Can be converted by:
--
--     local timer_start = awrap(vim.loop.timer_start)
--
-- timer_start now has the signature:
--
--     timer_start(timer, timeout, repeat): function(callback)
--

global type cb_function = function(function(...: any))
global type async_function = function(...: any): cb_function

local co = coroutine

local M = {}

function M.async(func: function): async_function
  return function(...): cb_function
    local params = {...}
    return function(callback: function)
      local thread = co.create(func)
      local function step(...: any)
        local stat, ret: boolean, any = co.resume(thread, ...)
        assert(stat, ret)
        if co.status(thread) == "dead" then
          if callback then
            callback(ret)
          end
        else
          (ret as function)(step)
        end
      end
      step(unpack(params))
    end
  end
end

-- Create a synchronous function which can await on async functions
function M.sync(func: function): function
  return function(...)
    M.async(func)(...)()
  end
end

-- Run an async function
function M.arun(func: async_function): function
  return function(...)
    func(...)()
  end
end

function M.awrap(func: function): function
  return function(...): cb_function
    local params = {...}
    return function(step: function): any...
      table.insert(params, step)
      return func(unpack(params))
    end
  end
end

function M.await(defer: async_function, ...: any): any...
  return co.yield(defer(...))
end

function M.await_main()
  co.yield(vim.schedule)
end

return M
