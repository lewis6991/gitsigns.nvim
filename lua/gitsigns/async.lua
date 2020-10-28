-- Originated from: https://github.com/ms-jpq/neovim-async-tutorial/blob/neo/lua/async.lua

local co = coroutine

local M = {}

M.async = function(name, func)
  assert(type(func) == "function", "type error :: expected func")
  local nparams = debug.getinfo(func, 'u').nparams
  -- print("async: "..name.." "..nparams)

  return function(...)
    local params = {...}
    local callback = params[nparams+1]

    assert(type(callback) == "function" or callback == nil, "type error :: expected func, got "..type(callback))

    local thread = co.create(func)
    local function step(...)
      local stat, ret = co.resume(thread, ...)
      assert(stat, ret)
      if co.status(thread) == "dead" then
        if callback then
          callback(ret)
        end
      else
        assert(type(ret) == "function", "type error :: expected func")
        ret(step)
      end
    end
    step(unpack(params, 1, nparams))
  end
end

M.async0 = function(name, fn)
  return function()
    M.async(name, fn)()
  end
end


M.awrap = function(func)
  assert(type(func) == "function", "type error :: expected func")
  return function(...)
    local params = {...}
    return function(step)
      table.insert(params, step)
      return func(unpack(params))
    end
  end
end


M.await = function(defer, ...)
  assert(type(defer) == "function", "type error :: expected func")
  return co.yield(M.awrap(defer)(...))
end

return M
