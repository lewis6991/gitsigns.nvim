local assert = require('luassert')
local luv = vim.loop
local Session = require('test.client.session')
local ProcessStream = require('test.client.uv_stream')

assert:set_parameter('TableFormatLevel', 100)

local M = {}

-- sleeps the test runner (_not_ the nvim instance)
function M.sleep(ms)
  luv.sleep(ms)
end

M.eq = assert.are.same
M.neq = assert.are_not.same

local function epicfail(state, arguments, _)
  --- @diagnostic disable-next-line
  state.failure_message = arguments[1]
  return false
end

--- @diagnostic disable-next-line:missing-parameter
assert:register("assertion", "epicfail", epicfail)

function M.matches(pat, actual)
  if nil ~= string.match(actual, pat) then
    return true
  end
  error(string.format('Pattern does not match.\nPattern:\n%s\nActual:\n%s', pat, actual))
end

--- Reads text lines from `filename` into a table.
---
--- filename: path to file
--- start: start line (1-indexed), negative means "lines before end" (tail)
--- @param filename string
--- @param start? integer
--- @return string[]?
local function read_file_list(filename, start)
  local lnum = start or 1
  local tail = lnum < 0
  local maxlines = tail and math.abs(lnum) or nil
  local file = io.open(filename, 'r')

  if not file then
    return
  end

  -- There is no need to read more than the last 2MB of the log file, so seek
  -- to that.
  local file_size = file:seek("end")
  local offset = file_size - 2000000
  if offset < 0 then
    offset = 0
  end
  file:seek("set", offset)

  local lines = {} --- @type string[]
  local i = 1
  local line = file:read("*l")
  while line do
    if i >= start then
      table.insert(lines, line)
      if #lines > maxlines then
        table.remove(lines, 1)
      end
    end
    i = i + 1
    line = file:read("*l")
  end
  file:close()
  return lines
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
  local errmsg = tostring(rv):gsub('([%s<])vim[/\\]([^%s:/\\]+):%d+', '%1\xffvim\xff%2:0')
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
  assert(type(fn) == 'function')
  local status, rv = M.pcall(fn, ...)
  if status == true then
    error('expected failure, but got success')
  end
  return rv
end

local function pcall_err_withtrace(fn, ...)
  local errmsg = pcall_err_withfile(fn, ...)

  return errmsg:gsub('^%.%.%./helpers%.lua:0: ', '')
               :gsub('^Error executing lua:- ' ,'')
               :gsub('^%[string "<nvim>"%]:0: ' ,'')
end

function M.pcall_err(...)
  return M.remove_trace(pcall_err_withtrace(...))
end

function M.remove_trace(s)
  return (s:gsub("\n%s*stack traceback:.*", ""))
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
  str = str:gsub('^'..indent, left_indent)
  -- strip it from the remaining lines
  str = str:gsub('[\n]'..indent, '\n' .. left_indent)
  return str
end

-- Gets the (tail) contents of `logfile`.
-- Also moves the file to "${NVIM_LOG_FILE}.displayed" on CI environments.
function M.read_nvim_log(logfile)
  logfile = logfile or os.getenv('NVIM_LOG_FILE') or '.nvimlog'
  local keep = 10
  local lines = read_file_list(logfile, -keep) or {}
  local log = (('-'):rep(78)..'\n'
    ..string.format('$NVIM_LOG_FILE: %s\n', logfile)
    ..(#lines > 0 and '(last '..tostring(keep)..' lines)\n' or '(empty)\n'))
  for _,line in ipairs(lines) do
    log = log..line..'\n'
  end
  log = log..('-'):rep(78)..'\n'
  return log
end

local runtime_set = 'set runtimepath^=./build/lib/nvim/'
local nvim_prog = os.getenv('NVIM_PRG') or 'nvim'
-- Default settings for the test session.
local nvim_set = table.concat({
  'set',
  'shortmess+=IS',
  'background=light',
  'noswapfile',
  'noautoindent',
  'startofline',
  'laststatus=1',
  'undodir=.',
  'directory=.',
  'viewdir=.',
  'backupdir=.',
  'belloff=',
  'wildoptions-=pum',
  'joinspaces',
  'noshowcmd', 'noruler', 'nomore',
  'redrawdebug=invalid'
}, ' ')

local nvim_argv = {
  nvim_prog,
  '-u', 'NONE',
  '-i', 'NONE',
  '--cmd', runtime_set,
  '--cmd', nvim_set,
  '--cmd', 'mapclear',
  '--cmd', 'mapclear!',
  '--embed',
  '--headless'
}

local session --- @type NvimSession?
local loop_running = false
local last_error --- @type string?

function M.get_session()
  return session
end

--- @param method string
--- @param ... any
--- @return any[]
local function request(method, ...)
  assert(session)
  local status, rv = session:request(method, ...)
  if not status then
    if loop_running then
      last_error = rv[2]
      session:stop()
    else
      error(rv[2])
    end
  end
  return rv
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

--- Executes an ex-command. VimL errors manifest as client (lua) errors, but
--- v:errmsg will not be updated.
--- @param cmd string
function M.command(cmd)
  request('nvim_command', cmd)
end

--- Evaluates a VimL expression.
--- Fails on VimL error, but does not update v:errmsg.
--- @param expr string
--- @return any[]
function M.eval(expr)
  return request('nvim_eval', expr)
end

--- Executes a VimL function via RPC.
--- Fails on VimL error, but does not update v:errmsg.
--- @param name string
--- @param ... any
--- @return any[]
function M.call(name, ...)
  return request('nvim_call_function', name, {...})
end

-- Checks that the Nvim session did not terminate.
local function assert_alive()
  assert(2 == M.eval('1+1'), 'crash? request failed')
end

--- Sends user input to Nvim.
--- Does not fail on VimL error, but v:errmsg will be updated.
--- @param input string
local function nvim_feed(input)
  while #input > 0 do
    local written = request('nvim_input', input)
    if written == nil then
      assert_alive()
      error('crash? (nvim_input returned nil)')
    end
    input = input:sub(written + 1)
  end
end

--- @param ... string
function M.feed(...)
  for _, v in ipairs({...}) do
    nvim_feed(M.dedent(v))
  end
end

--- @param ... string
local function rawfeed(...)
  for _, v in ipairs({...}) do
    nvim_feed(M.dedent(v))
  end
end

local function check_close()
  if not session then
    return
  end
  local start_time = luv.now()
  session:close()
  luv.update_time()  -- Update cached value of luv.now() (libuv: uv_now()).
  local end_time = luv.now()
  local delta = end_time - start_time
  if delta > 500 then
    print("nvim took " .. delta .. " milliseconds to exit after last test\n"..
          "This indicates a likely problem with the test even if it passed!\n")
    io.stdout:flush()
  end
  session = nil
end

--- Starts a new global Nvim session.
function M.clear()
  check_close()
  local child_stream = ProcessStream.spawn(nvim_argv)
  session = Session.new(child_stream)

  local status, info = session:request('nvim_get_api_info')
  assert(status)

  assert(session:request('nvim_exec_lua', [[
    local channel = ...
    local orig_error = error

    function error(...)
      vim.rpcnotify(channel, 'nvim_error_event', debug.traceback(), ...)
      return orig_error(...)
    end
    ]], {info[1]}))
end

---@param ... string
function M.insert(...)
  nvim_feed('i')
  for _, v in ipairs({...}) do
    local escaped = v:gsub('<', '<lt>')
    rawfeed(escaped)
  end
  nvim_feed('<ESC>')
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

function M.nvim(method, ...)
  return request('nvim_'..method, ...)
end

function M.buffer(method, ...)
  return request('nvim_buf_'..method, ...)
end

function M.window(method, ...)
  return request('nvim_win_'..method, ...)
end

function M.curbuf(method, ...)
  if not method then
    return M.nvim('get_current_buf')
  end
  return M.buffer(method, 0, ...)
end

function M.curwin(method, ...)
  if not method then
    return M.nvim('get_current_win')
  end
  return M.window(method, 0, ...)
end

M.funcs = M.create_callindex(M.call)
M.meths = M.create_callindex(M.nvim)
M.bufmeths = M.create_callindex(M.buffer)
M.winmeths = M.create_callindex(M.window)
M.curbufmeths = M.create_callindex(M.curbuf)
M.curwinmeths = M.create_callindex(M.curwin)

function M.exc_exec(cmd)
  M.command(([[
    try
      execute "%s"
    catch
      let g:__exception = v:exception
    endtry
  ]]):format(cmd:gsub('\n', '\\n'):gsub('[\\"]', '\\%0')))
  local ret = M.eval('get(g:, "__exception", 0)')
  M.command('unlet! g:__exception')
  return ret
end

function M.exec_capture(code)
  -- return module.meths.exec2(code, { output = true }).output
  return M.meths.exec(code, true)
end

function M.exec_lua(code, ...)
  return M.meths.exec_lua(code, {...})
end

--- @param after_each fun(block:fun())
function M.after_each(after_each)
  after_each(function()
    if not session then
      return
    end
    local msg = session:next_message(0)
    if msg then
      if msg[1] == "notification" and msg[2] == "nvim_error_event" then
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
    return it0(name..' #'..it_id..'#', test)
  end

  g.after_each(function()
    if not session then
      return
    end
    local msg = session:next_message(0)
    if msg then
      if msg[1] == "notification" and msg[2] == "nvim_error_event" then
        error(msg[3][2])
      end
    end
  end)
end

return M
