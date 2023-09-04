local uv = vim.loop

local M = {}

--- Debounces a function on the trailing edge.
---
--- @generic F: function
--- @param ms number Timeout in ms
--- @param fn F Function to debounce
--- @param hash? integer|fun(...): any Function that determines id from arguments to fn
--- @return F Debounced function.
function M.debounce_trailing(ms, fn, hash)
  local running = {} --- @type table<any,uv.uv_timer_t>
  if type(hash) == 'number' then
    local hash_i = hash
    hash = function(...)
      return select(hash_i, ...)
    end
  end
  return function(...)
    local id = hash and hash(...) or true
    if running[id] == nil then
      running[id] = assert(uv.new_timer())
    end
    local timer = running[id]
    local argv = { ... }
    timer:start(ms, 0, function()
      timer:stop()
      running[id] = nil
      fn(unpack(argv, 1, table.maxn(argv)))
    end)
  end
end

--- Throttles a function using the first argument as an ID
---
--- If function is already running then the function will be scheduled to run
--- again once the running call has finished.
---
---   fn#1            _/‾\__/‾\_/‾\_____________________________
---   throttled#1 _/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\/‾‾‾‾‾‾‾‾‾‾\____________
--
---   fn#2            ______/‾\___________/‾\___________________
---   throttled#2 ______/‾‾‾‾‾‾‾‾‾‾\__/‾‾‾‾‾‾‾‾‾‾\__________
---
---
--- @generic F: function
--- @param fn F Function to throttle
--- @param schedule? boolean
--- @return F throttled function.
function M.throttle_by_id(fn, schedule)
  local scheduled = {} --- @type table<any,boolean>
  local running = {} --- @type table<any,boolean>
  return function(id, ...)
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
