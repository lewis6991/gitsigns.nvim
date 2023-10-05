local assert = require('luassert')
local luv = vim.loop
local Session = require('test.client.session')
local ProcessStream = require('test.client.uv_stream')

assert:set_parameter('TableFormatLevel', 100)

local M = {}

M.sleep = luv.sleep

M.eq = assert.are.same
M.neq = assert.are_not.same

local function epicfail(state, arguments, _)
  --- @diagnostic disable-next-line
  state.failure_message = arguments[1]
  return false
end

--- @diagnostic disable-next-line:missing-parameter
assert:register('assertion', 'epicfail', epicfail)

function M.matches(pat, actual)
  if nil ~= string.match(actual, pat) then
    return true
  end
  error(string.format('Pattern does not match.\nPattern:\n%s\nActual:\n%s', pat, actual))
end

--- @generic R
--- @param fn fun(...): R
--- @param ... any arguments
--- @return boolean
--- @return R|string
function M.pcall(fn, ...)
  assert(type(fn) == 'function')
  local status, rv = pcall(fn, ...)
  if status then
    return status, rv
  end

  -- From:
  --    C:/long/path/foo.lua:186: Expected string, got number
  -- to:
  --    .../foo.lua:0: Expected string, got number
  local errmsg = tostring(rv)
    :gsub('([%s<])vim[/\\]([^%s:/\\]+):%d+', '%1\xffvim\xff%2:0')
    :gsub('[^%s<]-[/\\]([^%s:/\\]+):%d+', '.../%1:0')
    :gsub('\xffvim\xff', 'vim/')
  -- Scrub numbers in paths/stacktraces:
  --    shared.lua:0: in function 'gsplit'
  --    shared.lua:0: in function <shared.lua:0>'
  errmsg = errmsg:gsub('([^%s]):%d+', '%1:0')
  -- Scrub tab chars:
  errmsg = errmsg:gsub('\t', '    ')
  -- In Lua 5.1, we sometimes get a "(tail call): ?" on the last line.
  --    We remove this so that the tests are not lua dependent.
  errmsg = errmsg:gsub('%s*%(tail call%): %?', '')

  return status, errmsg
end

--- Invokes `fn` and returns the error string (with truncated paths), or raises
--- an error if `fn` succeeds.
---
--- Replaces line/column numbers with zero:
---     shared.lua:0: in function 'gsplit'
---     shared.lua:0: in function <shared.lua:0>'
---
--- Usage:
---    -- Match exact string.
---    eq('e', pcall_err(function(a, b) error('e') end, 'arg1', 'arg2'))
---    -- Match Lua pattern.
---    matches('e[or]+$', pcall_err(function(a, b) error('some error') end, 'arg1', 'arg2'))
---
--- @generic R
--- @param fn fun(...): R
--- @param ... any arguments
--- @return R
local function pcall_err_withfile(fn, ...)
  local status, rv = M.pcall(fn, ...)
  if status == true then
    error('expected failure, but got success')
  end
  return rv
end

local function pcall_err_withtrace(fn, ...)
  local errmsg = pcall_err_withfile(fn, ...)

  return errmsg
    :gsub('^%.%.%./helpers%.lua:0: ', '')
    :gsub('^Error executing lua:- ', '')
    :gsub('^%[string "<nvim>"%]:0: ', '')
end

function M.pcall_err(...)
  return M.remove_trace(pcall_err_withtrace(...))
end

function M.remove_trace(s)
  return (s:gsub('\n%s*stack traceback:.*', ''))
end

-- Concat list-like tables.
function M.concat_tables(...)
  local ret = {}
  for i = 1, select('#', ...) do
    local tbl = select(i, ...)
    if tbl then
      for _, v in ipairs(tbl) do
        ret[#ret + 1] = v
      end
    end
  end
  return ret
end

--- @param str string
--- @param leave_indent? integer
--- @return string
function M.dedent(str, leave_indent)
  -- find minimum common indent across lines
  local indent = nil --- @type string?
  for line in str:gmatch('[^\n]+') do
    local line_indent = line:match('^%s+') or ''
    if indent == nil or #line_indent < #indent then
      indent = line_indent
    end
  end
  if indent == nil or #indent == 0 then
    -- no minimum common indent
    return str
  end
  local left_indent = (' '):rep(leave_indent or 0)
  -- create a pattern for the indent
  indent = indent:gsub('%s', '[ \t]')
  -- strip it from the first line
  str = str:gsub('^' .. indent, left_indent)
  -- strip it from the remaining lines
  str = str:gsub('[\n]' .. indent, '\n' .. left_indent)
  return str
end

-- Default settings for the test session.
local nvim_set = table.concat({
  'set',
  'background=light',
  'noswapfile',
  'noautoindent',
  'startofline',
  'laststatus=1',
  'wildoptions-=pum',
  'joinspaces',
  'noshowcmd',
  'noruler',
  'nomore',
  'redrawdebug=invalid',
}, ' ')

local nvim_cmd = {
  os.getenv('NVIM_PRG') or 'nvim',
  '-u',
  'NONE',
  '-i',
  'NONE',
  '--cmd',
  nvim_set,
  '--embed',
  '--headless',
}

local session --- @type NvimSession?
local loop_running = false
local last_error --- @type string?

function M.get_session()
  return session
end

--- @param lsession NvimSession
--- @param ... any
--- @return string
local function call_and_stop_on_error(lsession, ...)
  local status, result = Session.safe_pcall(...)
  if not status then
    lsession:stop()
    last_error = result
    return ''
  end
  return result
end

--- @param lsession NvimSession
--- @param request_cb fun()?
--- @param notification_cb fun()?
--- @param timeout integer
--- @return unknown
function M.run_session(lsession, request_cb, notification_cb, timeout)
  local on_request --- @type function
  local on_notification --- @type function

  if request_cb then
    function on_request(method, args)
      return call_and_stop_on_error(lsession, request_cb, method, args)
    end
  end

  if notification_cb then
    function on_notification(method, args)
      call_and_stop_on_error(lsession, notification_cb, method, args)
    end
  end

  loop_running = true
  lsession:run(on_request, on_notification, nil, timeout)
  loop_running = false
  if last_error then
    local err = last_error
    last_error = nil
    error(err)
  end

  return lsession.eof_err
end

function M.create_callindex(func)
  return setmetatable({}, {
    --- @param tbl table<string,function>
    --- @param arg1 string
    --- @return function
    __index = function(tbl, arg1)
      local ret = function(...)
        return func(arg1, ...)
      end
      tbl[arg1] = ret
      return ret
    end,
  })
end

-- Trick LuaLS that M.api has the type of vim.api. vim.api is set to nil in
-- preload.lua so M.api gets the second term

M.api = vim.api
  or M.create_callindex(function(...)
    assert(session)
    local status, rv = session:request(...)
    if not status then
      if loop_running then
        last_error = rv[2]
        session:stop()
      else
        error(rv[2])
      end
    end
    return rv
  end)

M.fn = vim.fn
  or M.create_callindex(function(name, ...)
    return M.api.nvim_call_function(name, { ... })
  end)

function M.exec_lua(code, ...)
  return M.api.nvim_exec_lua(code, { ... })
end

-- Checks that the Nvim session did not terminate.
local function assert_alive()
  assert(2 == M.api.nvim_eval('1+1'), 'crash? request failed')
end

--- Sends user input to Nvim.
--- Does not fail on VimL error, but v:errmsg will be updated.
--- @param input string
local function nvim_feed(input)
  while #input > 0 do
    local written = M.api.nvim_input(input)
    if written == nil then
      assert_alive()
      error('crash? (nvim_input returned nil)')
    end
    input = input:sub(written + 1)
  end
end

--- @param ... string
function M.feed(...)
  for _, v in ipairs({ ... }) do
    nvim_feed(M.dedent(v))
  end
end

--- @param ... string
local function rawfeed(...)
  for _, v in ipairs({ ... }) do
    nvim_feed(M.dedent(v))
  end
end

local function check_close()
  if not session then
    return
  end
  local start_time = luv.now()
  session:close()
  luv.update_time() -- Update cached value of luv.now() (libuv: uv_now()).
  local end_time = luv.now()
  local delta = end_time - start_time
  if delta > 500 then
    print(
      'nvim took '
        .. delta
        .. ' milliseconds to exit after last test\n'
        .. 'This indicates a likely problem with the test even if it passed!\n'
    )
    io.stdout:flush()
  end
  session = nil
end

--- Starts a new global Nvim session.
function M.clear()
  check_close()
  local child_stream = ProcessStream.spawn(nvim_cmd)
  session = Session.new(child_stream)

  local status, info = session:request('nvim_get_api_info')
  assert(status)

  assert(session:request(
    'nvim_exec_lua',
    [[
    local channel = ...
    local orig_error = error

    function error(...)
      vim.rpcnotify(channel, 'nvim_error_event', debug.traceback(), ...)
      return orig_error(...)
    end
    ]],
    { info[1] }
  ))
end

---@param ... string
function M.insert(...)
  nvim_feed('i')
  for _, v in ipairs({ ... }) do
    local escaped = v:gsub('<', '<lt>')
    rawfeed(escaped)
  end
  nvim_feed('<ESC>')
end

function M.exc_exec(cmd)
  M.api.nvim_command(([[
    try
      execute "%s"
    catch
      let g:__exception = v:exception
    endtry
  ]]):format(cmd:gsub('\n', '\\n'):gsub('[\\"]', '\\%0')))
  local ret = M.api.nvim_eval('get(g:, "__exception", 0)')
  M.api.nvim_command('unlet! g:__exception')
  return ret
end

--- @param after_each fun(block:fun())
function M.after_each(after_each)
  after_each(function()
    if not session then
      return
    end
    local msg = session:next_message(0)
    if msg then
      if msg[1] == 'notification' and msg[2] == 'nvim_error_event' then
        error(msg[3][2])
      end
    end
  end)
end

local it_id = 0
function M.env()
  local g = getfenv(2)

  local it0 = g.it
  g.it = function(name, test)
    it_id = it_id + 1
    return it0(name .. ' #' .. it_id .. '#', test)
  end

  g.after_each(function()
    if not session then
      return
    end
    local msg = session:next_message(0)
    if msg then
      if msg[1] == 'notification' and msg[2] == 'nvim_error_event' then
        error(msg[3][2])
      end
    end
  end)
end

return M
