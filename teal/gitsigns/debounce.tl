local uv = require('gitsigns.uv')

local record M
  throttle_by_id    : function<F>(fn: F, schedule: boolean): F
  debounce_trailing : function<F>(ms: number, fn: F): F
end

--- Debounces a function on the trailing edge.
---
--- @generic F: function
--- @param ms number Timeout in ms
--- @param fn F Function to debounce
--- @return F Debounced function.
function M.debounce_trailing(ms: number, fn: function): function
  local timer = uv.new_timer(true)
  return function(...)
    local argv = {...}
    timer:start(ms, 0, function()
      timer:stop()
      fn(unpack(argv))
    end)
  end
end


--- Throttles a function on the leading edge.
---
--- @generic F: function
--- @param ms number Timeout in ms
--- @param fn F Function to throttle
--- @return F throttled function.
function M.throttle_leading(ms: number, fn: function): function
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

--- Throttles a function using the first argument as an ID
---
--- If function is already running then the function will be scheduled to run
--- again once the running call has finished.
---
---  fn#1        _/‾\__/‾\_/‾\_____________________________
---  throttled#1 _/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\/‾‾‾‾‾‾‾‾‾‾\____________
--
---  fn#2        ______/‾\___________/‾\___________________
---  throttled#2 ______/‾‾‾‾‾‾‾‾‾‾\__/‾‾‾‾‾‾‾‾‾‾\__________
---
---
--- @generic F: function
--- @param fn F Function to throttle
--- @param schedule boolean
--- @return F throttled function.
function M.throttle_by_id(fn: function, schedule: boolean): function
  local scheduled: {any:boolean} = {} --- @type table<any,boolean>
  local running: {any:boolean} = {} --- @type table<any,boolean>
  return function(id: any, ...)
    if scheduled[id] then
      -- If fn is already scheduled, then drop
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
