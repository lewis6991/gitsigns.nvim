local pcall = copcall or pcall

--- @generic T
--- @param ... T...
--- @return [T...] & { n: integer }
local function pack_len(...)
  --- @diagnostic disable-next-line: return-type-mismatch
  return { n = select('#', ...), ... }
end

--- like unpack() but use the length set by F.pack_len if present
--- @generic T, Start: integer, End: integer
--- @param t T & { n?: End }
--- @param first? Start
--- @return std.Unpack<T, Start, End>
local function unpack_len(t, first)
  -- EmmyLuaLs/emmylua-analyzer-rust#619
  --- @diagnostic disable-next-line: param-type-not-match, undefined-field, missing-return-value
  return unpack(t, first or 1, t.n or table.maxn(t --[[@as table]]))
end

--- @class Gitsigns.async
local M = {}

--- Weak table to keep track of running tasks
--- @type table<thread,Gitsigns.async.Task?>
local threads = setmetatable({}, { __mode = 'k' })

--- @return Gitsigns.async.Task?
local function running()
  local task = threads[coroutine.running()]
  if task and not (task:_completed() or task._closing) then
    return task
  end
end

--- Base class for async tasks. Async functions should return a subclass of
--- this. This is designed specifically to be a base class of uv_handle_t
--- @class Gitsigns.async.Handle
--- @field close fun(self: Gitsigns.async.Handle, callback?: fun())
--- @field is_closing? fun(self: Gitsigns.async.Handle): boolean

--- @alias Gitsigns.async.CallbackFn fun(...: any): Gitsigns.async.Handle?

--- @class Gitsigns.async.Task<R> : Gitsigns.async.Handle
--- @field package _callbacks table<integer,fun(err?: any, ...:R...)>
--- @field package _callback_pos integer
--- @field private _thread thread
---
--- Tasks can call other async functions (task of callback functions)
--- when we are waiting on a child, we store the handle to it here so we can
--- cancel it.
--- @field private _current_child? Gitsigns.async.Handle
---
--- Error result of the task is an error occurs.
--- Must use `await` to get the result.
--- @field private _err? any
---
--- Result of the task.
--- Must use `await` to get the result.
--- @field private _result? R[]
local Task = {}
Task.__index = Task

--- @private
--- @param func function
--- @return Gitsigns.async.Task
function Task._new(func)
  local thread = coroutine.create(func)

  --- @type Gitsigns.async.Task
  local self = setmetatable({
    _closing = false,
    _thread = thread,
    _callbacks = {},
    _callback_pos = 1,
  }, Task)

  threads[thread] = self

  return self
end

--- @param callback fun(err?: any, ...: any)
function Task:await(callback)
  if self._closing then
    callback('closing')
  elseif self:_completed() then -- TODO(lewis6991): test
    -- Already finished or closed
    callback(self._err, unpack_len(self._result or {}))
  else
    self._callbacks[self._callback_pos] = callback
    self._callback_pos = self._callback_pos + 1
  end
end

--- @package
function Task:_completed()
  return (self._err or self._result) ~= nil
end

-- Use max 32-bit signed int value to avoid overflow on 32-bit systems.
-- Do not use `math.huge` as it is not interpreted as a positive integer on all
-- platforms.
local MAX_TIMEOUT = 2 ^ 31 - 1

--- Synchronously wait (protected) for a task to finish (blocking)
---
--- If an error is returned, `Task:traceback()` can be used to get the
--- stack trace of the error.
---
--- Example:
--- ```lua
---
---   local ok, err_or_result = task:pwait(10)
---
---   if not ok then
---     error(task:traceback(err_or_result))
---   end
---
---   local _, result = assert(task:pwait(10))
--- ```
---
--- Can be called if a task is closing.
--- @param timeout? integer
--- @return boolean status
--- @return any ... result or error
function Task:pwait(timeout)
  local done = vim.wait(timeout or MAX_TIMEOUT, function()
    -- Note we use self:_completed() instead of self:await() to avoid creating a
    -- callback. This avoids having to cleanup/unregister any callback in the
    -- case of a timeout.
    return self:_completed()
  end)

  if not done then
    return false, 'timeout'
  elseif self._err then
    return false, self._err
  else
    return true, unpack_len(assert(self._result))
  end
end

--- Synchronously wait for a task to finish (blocking)
---
--- Example:
--- ```lua
---   local result = task:wait(10) -- wait for 10ms or else error
---
---   local result = task:wait() -- wait indefinitely
--- ```
--- @param timeout? integer Timeout in milliseconds
--- @return R... result
function Task:wait(timeout)
  local res = pack_len(self:pwait(timeout))
  local stat = res[1]

  if not stat then
    error(self:traceback(res[2]))
  end

  return unpack_len(res, 2)
end

--- @private
--- @param msg? string
--- @param _lvl? integer
--- @return string
function Task:_traceback(msg, _lvl)
  _lvl = _lvl or 0

  local thread = ('[%s] '):format(self._thread)

  local child = self._current_child
  if getmetatable(child) == Task then
    --- @cast child Gitsigns.async.Task
    msg = child:_traceback(msg, _lvl + 1)
  end

  local tblvl = getmetatable(child) == Task and 2 or nil
  msg = (msg or '') .. debug.traceback(self._thread, '', tblvl):gsub('\n\t', '\n\t' .. thread)

  if _lvl == 0 then
    --- @type string
    msg = msg
      :gsub('\nstack traceback:\n', '\nSTACK TRACEBACK:\n', 1)
      :gsub('\nstack traceback:\n', '\n')
      :gsub('\nSTACK TRACEBACK:\n', '\nstack traceback:\n', 1)
  end

  return msg
end

--- Get the traceback of a task when it is not active.
--- Will also get the traceback of nested tasks.
---
--- @param msg? string
--- @return string
function Task:traceback(msg)
  return self:_traceback(msg)
end

--- If a task completes with an error, raise the error
function Task:raise_on_error()
  self:await(function(err)
    if err then
      error(self:_traceback(err), 0)
    end
  end)
  return self
end

--- @private
--- @param err? any
--- @param result? any[] & { n: integer }
function Task:_finish(err, result)
  self._current_child = nil
  self._err = err
  self._result = result
  threads[self._thread] = nil

  local errs = {} --- @type string[]
  for _, cb in pairs(self._callbacks) do
    --- @type boolean
    local ok, cb_err = pcall(cb, err, unpack_len(result or {}))
    if not ok then
      errs[#errs + 1] = cb_err
    end
  end

  if #errs > 0 then
    error(table.concat(errs, '\n'), 0)
  end
end

--- @return boolean
function Task:is_closing()
  return self._closing
end

--- Close the task and all its children.
--- If callback is provided it will run asynchronously,
--- else it will run synchronously.
---
--- @param callback? fun()
function Task:close(callback)
  if self:_completed() then
    if callback then
      callback()
    end
    return
  end

  if self._closing then
    return
  end

  self._closing = true

  if callback then -- async
    if self._current_child then
      self._current_child:close(function()
        self:_finish('closed')
        callback()
      end)
    else
      self:_finish('closed')
      callback()
    end
  else -- sync
    if self._current_child then
      self._current_child:close(function()
        self:_finish('closed')
      end)
    else
      self:_finish('closed')
    end
    vim.wait(0, function()
      return self:_completed()
    end)
  end
end

--- @param obj any
--- @return boolean
local function is_async_handle(obj)
  local ty = type(obj)
  return (ty == 'table' or ty == 'userdata') and vim.is_callable(obj.close)
end

--- @param ... any
function Task:_resume(...)
  --- @diagnostic disable-next-line: assign-type-mismatch
  --- @type [boolean, string|Gitsigns.async.CallbackFn]
  local ret = pack_len(coroutine.resume(self._thread, ...))
  local stat = ret[1]

  if not stat then
    -- Coroutine had error
    self:_finish(ret[2])
  elseif coroutine.status(self._thread) == 'dead' then
    -- Coroutine finished
    local result = pack_len(unpack_len(ret, 2))
    self:_finish(nil, result)
  else
    local fn = ret[2]
    --- @cast fn -string

    -- TODO(lewis6991): refine error handler to be more specific
    local ok, r
    ok, r = pcall(fn, function(...)
      if is_async_handle(r) then
        --- @cast r Gitsigns.async.Handle
        -- We must close children before we resume to ensure
        -- all resources are collected.
        local args = pack_len(...)
        r:close(function()
          self:_resume(unpack_len(args))
        end)
      else
        self:_resume(...)
      end
    end)

    if not ok then
      self:_finish(r)
    elseif is_async_handle(r) then
      self._current_child = r
    end
  end
end

--- @package
function Task:_log(...)
  print(self._thread, ...)
end

--- @return 'running'|'suspended'|'normal'|'dead'?
function Task:status()
  return coroutine.status(self._thread)
end

--- Run a function in an async context, asynchronously.
---
--- Examples:
--- ```lua
--- -- The two below blocks are equivalent:
---
--- -- Run a uv function and wait for it
--- local stat = async.run(function()
---     return async.await(2, vim.uv.fs_stat, 'foo.txt')
--- end):wait()
---
--- -- Since uv functions have sync versions. You can just do:
--- local stat = vim.fs_stat('foo.txt')
--- ```
--- @generic T, R
--- @param func async fun(...:T...): R...
--- @param ... T...
--- @return Gitsigns.async.Task<R>
function M.run(func, ...)
  local task = Task._new(func)
  task:_resume(...)
  return task
end

--- Returns the status of a task’s thread.
---
--- @param task? Gitsigns.async.Task
--- @return 'running'|'suspended'|'normal'|'dead'?
function M.status(task)
  task = task or running()
  if task then
    assert(getmetatable(task) == Task, 'Expected Task')
    return task:status()
  end
end

--- @async
--- @param task Gitsigns.async.Task
--- @return any ...
local function await_task(task)
  --- @param callback fun(err?: string, ...: any)
  local res = pack_len(coroutine.yield(function(callback)
    task:await(callback)
    return task
  end))

  local err = res[1]

  if err then
    -- TODO(lewis6991): what is the correct level to pass?
    error(err, 0)
  end

  return unpack_len(res, 2)
end

--- @async
--- Asynchronous blocking wait
--- @generic T, R
--- @param argc integer
--- @param fun fun(...:T..., cb: fun(...:R...))
--- @param ... T...
--- @return R......
local function await_cbfun(argc, fun, ...)
  local args = pack_len(...)

  --- @param callback fun(...:any)
  --- @return any?
  return coroutine.yield(function(callback)
    args[argc] = callback
    args.n = math.max(args.n, argc)
    --- @diagnostic disable-next-line: missing-parameter
    return fun(unpack_len(args))
  end)
end

--- Asynchronous blocking wait
---
--- Example:
--- ```lua
--- local task = async.run(function()
---    return 1, 'a'
--- end)
---
--- async.run(function()
---   do -- await a callback function
---     async.await(1, vim.schedule)
---   end
---
---   do -- await a task (new async context)
---     local n, s = async.await(task)
---     assert(n == 1 and s == 'a')
---   end
--- end)
--- ```
--- @async
--- @overload fun(func: Gitsigns.async.CallbackFn): any ...
--- @overload fun(argc: integer, func: Gitsigns.async.CallbackFn, ...:any): any ...
--- @overload fun(task: Gitsigns.async.Task): any ...
function M.await(...)
  assert(running(), 'Not in async context')

  local arg1 = select(1, ...)

  if type(arg1) == 'number' then
    return await_cbfun(...)
  elseif type(arg1) == 'function' then
    return await_cbfun(1, ...)
  elseif getmetatable(arg1) == Task then
    return await_task(...)
  end

  error('Invalid arguments, expected Task or (argc, func) got: ' .. type(arg1), 2)
end

--- Creates an async function with a callback style function.
---
--- Example:
---
--- ```lua
--- --- Note the callback argument is not present in the return function
--- --- @type fun(timeout: integer)
--- local sleep = async.wrap(2, function(timeout, callback)
---   local timer = vim.uv.new_timer()
---   timer:start(timeout * 1000, 0, callback)
---   -- uv_timer_t provides a close method so timer will be
---   -- cleaned up when this function finishes
---   return timer
--- end)
---
--- async.run(function()
---   print('hello')
---   sleep(2)
---   print('world')
--- end)
--- ```
---
--- local atimer = async.awrap(
--- @generic T, R
--- @param argc integer
--- @param func fun(...:T..., cb: fun(...:R...)): any
--- @return async fun(...:T...):R...
function M.wrap(argc, func)
  assert(type(argc) == 'number')
  assert(type(func) == 'function')
  --- @async
  return function(...)
    return M.await(argc, func, ...)
  end
end

if vim.schedule then
  --- An async function that when called will yield to the Neovim scheduler to be
  --- able to call the API.
  M.schedule = M.wrap(1, vim.schedule)
end

do --- M.event()
  --- An event can be used to notify multiple tasks that some event has
  --- happened. An Event object manages an internal flag that can be set to true
  --- with the `set()` method and reset to `false` with the `clear()` method.
  --- The `wait()` method blocks until the flag is set to `true`. The flag is
  --- set to `false` initially.
  --- @class Gitsigns.async.Event
  --- @field private _is_set boolean
  --- @field private _waiters function[]
  local Event = {}
  Event.__index = Event

  --- Set the event.
  ---
  --- All tasks waiting for event to be set will be immediately awakened.
  --- @param max_woken? integer
  function Event:set(max_woken)
    if self._is_set then
      return
    end
    self._is_set = true
    local waiters = self._waiters
    local waiters_to_notify = {} --- @type function[]
    max_woken = max_woken or #waiters
    while #waiters > 0 and #waiters_to_notify < max_woken do
      waiters_to_notify[#waiters_to_notify + 1] = table.remove(waiters, 1)
    end
    if #waiters > 0 then
      self._is_set = false
    end
    for _, waiter in ipairs(waiters_to_notify) do
      waiter()
    end
  end

  --- Wait until the event is set.
  ---
  --- If the event is set, return `true` immediately. Otherwise block until
  --- another task calls set().
  --- @async
  function Event:wait()
    M.await(function(callback)
      if self._is_set then
        callback()
      else
        table.insert(self._waiters, callback)
      end
    end)
  end

  --- Clear (unset) the event.
  ---
  --- Tasks awaiting on wait() will now block until the set() method is called
  --- again.
  function Event:clear()
    self._is_set = false
  end

  --- Create a new event
  ---
  --- An event can signal to multiple listeners to resume execution
  --- The event can be set from a non-async context.
  ---
  --- ```lua
  ---  local event = vim.async.event()
  ---
  ---  local worker = vim.async.run(function()
  ---    sleep(1000)
  ---    event.set()
  ---  end)
  ---
  ---  local listeners = {
  ---    vim.async.run(function()
  ---      event.wait()
  ---      print("First listener notified")
  ---    end),
  ---    vim.async.run(function()
  ---      event.wait()
  ---      print("Second listener notified")
  ---    end),
  ---  }
  --- ```
  --- @return Gitsigns.async.Event
  function M.event()
    return setmetatable({
      _waiters = {},
      _is_set = false,
    }, Event)
  end
end

do --- M.semaphore()
  --- A semaphore manages an internal counter which is decremented by each
  --- `acquire()` call and incremented by each `release()` call. The counter can
  --- never go below zero; when `acquire()` finds that it is zero, it blocks,
  --- waiting until some task calls `release()`.
  ---
  --- The preferred way to use a Semaphore is with the `with()` method, which
  --- automatically acquires and releases the semaphore around a function call.
  --- @class Gitsigns.async.Semaphore
  --- @field private _permits integer
  --- @field private _max_permits integer
  --- @field package _event Gitsigns.async.Event
  local Semaphore = {}
  Semaphore.__index = Semaphore

  --- Executes the given function within the semaphore's context, ensuring
  --- that the semaphore's constraints are respected.
  --- @async
  --- @generic R
  --- @param fn async fun(): R... # Function to execute within the semaphore's context.
  --- @return R... # Result(s) of the executed function.
  function Semaphore:with(fn)
    self:acquire()
    local r = pack_len(pcall(fn))
    self:release()
    local stat = r[1]
    if not stat then
      --- @diagnostic disable-next-line: undefined-field
      local err = r[2]
      error(err)
    end
    return unpack_len(r, 2)
  end

  --- Acquire a semaphore.
  ---
  --- If the internal counter is greater than zero, decrement it by `1` and
  --- return immediately. If it is `0`, wait until a `release()` is called.
  --- @async
  function Semaphore:acquire()
    self._event:wait()
    self._permits = self._permits - 1
    assert(self._permits >= 0, 'Semaphore value is negative')
    if self._permits == 0 then
      self._event:clear()
    end
  end

  --- Release a semaphore.
  ---
  --- Increments the internal counter by `1`. Can wake
  --- up a task waiting to acquire the semaphore.
  function Semaphore:release()
    if self._permits >= self._max_permits then
      error('Semaphore value is greater than max permits', 2)
    end
    self._permits = self._permits + 1
    self._event:set(1)
  end

  --- Create an async semaphore that allows up to a given number of acquisitions.
  ---
  --- ```lua
  --- vim.async.run(function()
  ---   local semaphore = vim.async.semaphore(2)
  ---
  ---   local tasks = {}
  ---
  ---   local value = 0
  ---   for i = 1, 10 do
  ---     tasks[i] = vim.async.run(function()
  ---       semaphore:with(function()
  ---         value = value + 1
  ---         sleep(10)
  ---         print(value) -- Never more than 2
  ---         value = value - 1
  ---       end)
  ---     end)
  ---   end
  ---
  ---   vim.async.join(tasks)
  ---   assert(value <= 2)
  --- end)
  --- ```
  --- @param permits? integer (default: 1)
  --- @return Gitsigns.async.Semaphore
  function M.semaphore(permits)
    permits = permits or 1
    local obj = setmetatable({
      _max_permits = permits,
      _permits = permits,
      _event = M.event(),
    }, Semaphore)
    obj._event:set()
    return obj
  end
end

return M
