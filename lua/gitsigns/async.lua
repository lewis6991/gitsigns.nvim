-- Originated from: https://github.com/ms-jpq/neovim-async-tutorial/blob/neo/lua/async.lua

local co = coroutine


-- use with wrap
local pong = function (func, callback)
  assert(type(func) == "function", "type error :: expected func")
  local thread = co.create(func)
  local step = nil
  step = function (...)
    local stat, ret = co.resume(thread, ...)
    assert(stat, ret)
    if co.status(thread) == "dead" then
      (callback or function () end)(ret)
    else
      assert(type(ret) == "function", "type error :: expected func")
      ret(step)
    end
  end
  step()
end


local awrap = function (func)
  assert(type(func) == "function", "type error :: expected func")
  return function(...)
    local params = {...}
    return function(step)
      table.insert(params, step)
      return func(unpack(params))
    end
  end
end


-- many thunks -> single thunk
local join = function (thunks)
  return function (step)
    if #thunks == 0 then
      return step()
    end
    local to_go = #thunks
    local results = {}
    for i, thunk in ipairs(thunks) do
      assert(type(thunk) == "function", "thunk must be function")
      local callback = function (...)
        results[i] = {...}
        if to_go == 1 then
          step(unpack(results))
        else
          to_go = to_go - 1
        end
      end
      thunk(callback)
    end
  end
end


-- sugar over coroutine
local await = function(defer)
  assert(type(defer) == "function", "type error :: expected func")
  return co.yield(defer)
end

local await_all = function(defer)
  assert(type(defer) == "table", "type error :: expected table")
  return co.yield(join(defer))
end

return {
  async      = awrap(pong),
  await      = await,
  await_all  = await_all,
  awrap      = awrap,
}
