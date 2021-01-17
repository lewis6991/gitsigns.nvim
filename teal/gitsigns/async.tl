-- Originated from: https://github.com/ms-jpq/neovim-async-tutorial/blob/neo/lua/async.lua

local co = coroutine

local M = {}

function M.async(name: string, func: function): function -- luacheck: ignore
  assert(type(func) == "function", "type error :: expected func")
  local nparams = debug.getinfo(func, 'u').nparams
  -- print("async: "..name.." "..nparams)

  return function(...)
    local params = {...}
    local callback = params[nparams+1] as function

    assert(type(callback) == "function" or callback == nil, "type error :: expected func, got "..type(callback))

    local thread = co.create(func)
    local function step(...:any)
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
    step(unpack(params, 1, nparams))
  end
end

function M.async0(name: string, fn: function): function
  return function()
    M.async(name, fn)()
  end
end


function M.awrap(func: function): function
  assert(type(func) == "function", "type error :: expected func")
  return function(...): function
    local params = {...}
    return function(step): any
      table.insert(params, step)
      return func(unpack(params))
    end
  end
end


function M.await(defer: function, ...: any): any...
  return co.yield(M.awrap(defer)(...))
end

function M.await_main(): any
  return M.await(vim.schedule)
end

return M
