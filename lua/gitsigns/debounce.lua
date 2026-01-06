local uv = vim.uv or vim.loop ---@diagnostic disable-line: deprecated

local M = {}

--- Debounces a function on the trailing edge.
---
--- Example waveform
---   Time:      0  1  2  3  4  5  6  7  8  9
---   Input:     |  |     |           |
---   Debounced:          |                 |
---
---   In this example, the function is called at times 0, 1, 3, and 7.
---   With a debounce period of 3 units, the debounced function fires at 3 and 9.
---
--- @generic F: function
--- @param timeout integer|fun():integer Timeout in ms
--- @param fn F Function to debounce
--- @param hash? integer|fun(...): any Function that determines id from arguments to fn
--- @return F Debounced function.
function M.debounce_trailing(timeout, fn, hash)
  local running = {} --- @type table<any, uv.uv_timer_t>

  -- Normalize hash to a function if it's a number (argument index)
  if type(hash) == 'number' then
    local hash_i = hash
    hash = function(...)
      return select(hash_i, ...)
    end
  elseif type(hash) ~= 'function' then
    hash = nil
  end

  -- Normalize ms to a function if it's a number
  if type(timeout) == 'number' then
    local ms_i = timeout
    timeout = function()
      return ms_i
    end
  end

  return function(...)
    local id = hash and hash(...) or true
    local argv = { ... }

    local timer = running[id]
    if not timer or timer:is_closing() then
      timer = assert(uv.new_timer())
      running[id] = timer
    end

    timer:stop() -- Always stop before (re)starting
    timer:start(timeout(), 0, function()
      timer:stop()
      running[id] = nil
      fn(unpack(argv, 1, table.maxn(argv)))
      timer:close()
    end)
  end
end

--- @class gitsigns.debounce.throttle_async.Opts
--- @field hash? integer|fun(...): any Function that determines id from arguments to fn
--- @field schedule? boolean If true, always schedule next call if called while running

--- Throttles an async function using the first argument as an ID
---
--- If function is already running then the function will be scheduled to run
--- again once the running call has finished.
---
--- ```
--- fn#1                        _/‾\__/‾\_/‾\____________________________
--- throttled#1[schedule=false] _/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_______________________
--- throttled#1[schedule=true]  _/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\/‾‾‾‾‾‾‾‾‾‾\___________
---
--- fn#2                        ______/‾\___________/‾\___________________
--- throttled#2[schedule=true]  ______/‾‾‾‾‾‾‾‾‾‾\__/‾‾‾‾‾‾‾‾‾‾\__________
--- throttled#2[schedule=false] ______/‾‾‾‾‾‾‾‾‾‾\__/‾‾‾‾‾‾‾‾‾‾\__________
--- ```
---
--- @generic T
--- @param opts gitsigns.debounce.throttle_async.Opts
--- @param fn async fun(...: T...) Function to throttle
--- @return async fun(...:T ...) # Throttled function.
function M.throttle_async(opts, fn)
  local scheduled = {} --- @type table<any,boolean>
  local running = {} --- @type table<any,boolean>

  local hash = opts.hash
  local schedule = opts.schedule or false

  -- Normalize hash to a function if it's a number (argument index)
  if type(hash) == 'number' then
    local hash_i = hash
    hash = function(...)
      return select(hash_i, ...)
    end
  elseif type(hash) ~= 'function' then
    hash = nil
  end

  --- @async
  return function(...)
    local id = hash and hash(...) or true
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
      fn(...)
      running[id] = nil
    end
  end
end

return M
