local M = {}

--- Debounces a function on the trailing edge.
---
--@param ms (number) Timeout in ms
--@param fn (function) Function to debounce
--@returns (function) Debounced function.
function M.debounce_trailing(ms: number, fn: function): function
  local timer = vim.loop.new_timer()
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
--@param ms (number) Timeout in ms
--@param fn (function) Function to throttle
--@returns (function) throttled function.
function M.throttle_leading(ms: number, fn: function): function
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
