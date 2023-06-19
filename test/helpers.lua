local assert = require('luassert')
local busted = require('busted')
local luv = require('luv')
local Session = require('test.client.session')
local uv_stream = require('test.client.uv_stream')
local ChildProcessStream = uv_stream.ChildProcessStream

assert:set_parameter('TableFormatLevel', 100)

local M = {}

-- sleeps the test runner (_not_ the nvim instance)
function M.sleep(ms)
  luv.sleep(ms)
end

-- Calls fn() until it succeeds, up to `max` times or until `max_ms`
-- milliseconds have passed.
function M.retry(max, max_ms, fn)
  assert(max == nil or max > 0)
  assert(max_ms == nil or max_ms > 0)
  local tries = 1
  local timeout = (max_ms and max_ms or 10000)
  local start_time = luv.now()
  while true do
    local status, result = pcall(fn)
    if status then
      return result
    end
    luv.update_time()  -- Update cached value of luv.now() (libuv: uv_now()).
    if (max and tries >= max) or (luv.now() - start_time > timeout) then
      busted.fail(string.format("retry() attempts: %d\n%s", tries, tostring(result)), 2)
    end
    tries = tries + 1
    luv.sleep(20)  -- Avoid hot loop...
  end
end

M.eq = assert.are.same
M.neq = assert.are_not.same

local function epicfail(state, arguments, _)
  state.failure_message = arguments[1]
  return false
end

assert:register("assertion", "epicfail", epicfail)

function M.matches(pat, actual)
  if nil ~= string.match(actual, pat) then
    return true
  end
  error(string.format('Pattern does not match.\nPattern:\n%s\nActual:\n%s', pat, actual))
end

-- Reads text lines from `filename` into a table.
--
-- filename: path to file
-- start: start line (1-indexed), negative means "lines before end" (tail)
local function read_file_list(filename, start)
  local lnum = (start ~= nil and type(start) == 'number') and start or 1
  local tail = (lnum < 0)
  local maxlines = tail and math.abs(lnum) or nil
  local file = io.open(filename, 'r')
  if not file then
    return nil
  end

  -- There is no need to read more than the last 2MB of the log file, so seek
  -- to that.
  local file_size = file:seek("end")
  local offset = file_size - 2000000
  if offset < 0 then
    offset = 0
  end
  file:seek("set", offset)

  local lines = {}
  local i = 1
  local line = file:read("*l")
  while line ~= nil do
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

-- Invokes `fn` and returns the error string (with truncated paths), or raises
-- an error if `fn` succeeds.
--
-- Replaces line/column numbers with zero:
--     shared.lua:0: in function 'gsplit'
--     shared.lua:0: in function <shared.lua:0>'
--
-- Usage:
--    -- Match exact string.
--    eq('e', pcall_err(function(a, b) error('e') end, 'arg1', 'arg2'))
--    -- Match Lua pattern.
--    matches('e[or]+$', pcall_err(function(a, b) error('some error') end, 'arg1', 'arg2'))
--
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

function M.dedent(str, leave_indent)
  -- find minimum common indent across lines
  local indent = nil
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
  '--embed'
}

local prepend_argv

if prepend_argv then
  local new_nvim_argv = {}
  local len = #prepend_argv
  for i = 1, len do
    new_nvim_argv[i] = prepend_argv[i]
  end
  for i = 1, #nvim_argv do
    new_nvim_argv[i + len] = nvim_argv[i]
  end
  nvim_argv = new_nvim_argv
  M.prepend_argv = prepend_argv
end

local session, loop_running, last_error

function M.get_session()
  return session
end

local function request(method, ...)
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

local function call_and_stop_on_error(lsession, ...)
  local status, result = Session.safe_pcall(...)
  if not status then
    lsession:stop()
    last_error = result
    return ''
  end
  return result
end

function M.run_session(lsession, request_cb, notification_cb, timeout)
  local on_request, on_notification

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

---- Executes an ex-command. VimL errors manifest as client (lua) errors, but
---- v:errmsg will not be updated.
function M.command(cmd)
  request('nvim_command', cmd)
end

---- Evaluates a VimL expression.
---- Fails on VimL error, but does not update v:errmsg.
function M.eval(expr)
  return request('nvim_eval', expr)
end

---- Executes a VimL function via RPC.
---- Fails on VimL error, but does not update v:errmsg.
function M.call(name, ...)
  return request('nvim_call_function', name, {...})
end

-- Checks that the Nvim session did not terminate.
local function assert_alive()
  assert(2 == M.eval('1+1'), 'crash? request failed')
end

---- Sends user input to Nvim.
---- Does not fail on VimL error, but v:errmsg will be updated.
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

function M.feed(...)
  for _, v in ipairs({...}) do
    nvim_feed(M.dedent(v))
  end
end

local function rawfeed(...)
  for _, v in ipairs({...}) do
    nvim_feed(M.dedent(v))
  end
end

local function merge_args(...)
  local i = 1
  local argv = {}
  for anum = 1,select('#', ...) do
    local args = select(anum, ...)
    if args then
      for _, arg in ipairs(args) do
        argv[i] = arg
        i = i + 1
      end
    end
  end
  return argv
end

--  Removes Nvim startup args from `args` matching items in `args_rm`.
--
--  - Special case: "-u", "-i", "--cmd" are treated specially: their "values" are also removed.
--  - Special case: "runtimepath" will remove only { '--cmd', 'set runtimepath^=…', }
--
--  Example:
--      args={'--headless', '-u', 'NONE'}
--      args_rm={'--cmd', '-u'}
--  Result:
--      {'--headless'}
--
--  All matching cases are removed.
--
--  Example:
--      args={'--cmd', 'foo', '-N', '--cmd', 'bar'}
--      args_rm={'--cmd', '-u'}
--  Result:
--      {'-N'}
local function remove_args(args, args_rm)
  local new_args = {}
  local skip_following = {'-u', '-i', '-c', '--cmd', '-s', '--listen'}
  if not args_rm or #args_rm == 0 then
    return {unpack(args)}
  end
  for _, v in ipairs(args_rm) do
    assert(type(v) == 'string')
  end
  local last = ''
  for _, arg in ipairs(args) do
    if vim.tbl_contains(skip_following, last) then
      last = ''
    elseif vim.tbl_contains(args_rm, arg) then
      last = arg
    elseif arg == runtime_set and vim.tbl_contains(args_rm, 'runtimepath') then
      table.remove(new_args)  -- Remove the preceding "--cmd".
      last = ''
    else
      table.insert(new_args, arg)
    end
  end
  return new_args
end

function M.check_close()
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

--- @param io_extra used for stdin_fd, see :help ui-option
function M.spawn(argv, merge, env, keep, io_extra)
  if not keep then
    M.check_close()
  end

  local child_stream = ChildProcessStream.spawn(
      merge and merge_args(prepend_argv, argv) or argv,
      env, io_extra)
  return Session.new(child_stream)
end

-- Builds an argument list for use in clear().
--
---@see clear() for parameters.
local function new_argv(...)
  local args = {unpack(nvim_argv)}
  table.insert(args, '--headless')
  if _G._nvim_test_id then
    -- Set the server name to the test-id for logging. #8519
    table.insert(args, '--listen')
    table.insert(args, _G._nvim_test_id)
  end
  local new_args
  local io_extra
  local env = nil
  local opts = select(1, ...)
  if type(opts) ~= 'table' then
    new_args = {...}
  else
    args = remove_args(args, opts.args_rm)
    if opts.env then
      local env_opt = {}
      for k, v in pairs(opts.env) do
        assert(type(k) == 'string')
        assert(type(v) == 'string')
        env_opt[k] = v
      end
      for _, k in ipairs({
        'HOME',
        'ASAN_OPTIONS',
        'TSAN_OPTIONS',
        'MSAN_OPTIONS',
        'LD_LIBRARY_PATH',
        'PATH',
        'NVIM_LOG_FILE',
        'NVIM_RPLUGIN_MANIFEST',
        'GCOV_ERROR_FILE',
        'XDG_DATA_DIRS',
        'TMPDIR',
        'VIMRUNTIME',
      }) do
        -- Set these from the environment unless the caller defined them.
        if not env_opt[k] then
          env_opt[k] = os.getenv(k)
        end
      end
      env = {}
      for k, v in pairs(env_opt) do
        env[#env + 1] = k .. '=' .. v
      end
    end
    new_args = opts.args or {}
    io_extra = opts.io_extra
  end
  for _, arg in ipairs(new_args) do
    table.insert(args, arg)
  end
  return args, env, io_extra
end

-- same params as clear, but does returns the session instead
-- of replacing the default session
local function spawn_argv(keep, ...)
  local argv, env, io_extra = new_argv(...)
  return M.spawn(argv, nil, env, keep, io_extra)
end

-- Starts a new global Nvim session.
--
-- Parameters are interpreted as startup args, OR a map with these keys:
--    args:       List: Args appended to the default `nvim_argv` set.
--    args_rm:    List: Args removed from the default set. All cases are
--                removed, e.g. args_rm={'--cmd'} removes all cases of "--cmd"
--                (and its value) from the default set.
--    env:        Map: Defines the environment of the new session.
--
-- Example:
--    clear('-e')
--    clear{args={'-e'}, args_rm={'-i'}, env={TERM=term}}
function M.clear(...)
  session = spawn_argv(false, ...)
end

function M.insert(...)
  nvim_feed('i')
  for _, v in ipairs({...}) do
    local escaped = v:gsub('<', '<lt>')
    rawfeed(escaped)
  end
  nvim_feed('<ESC>')
end

function M.create_callindex(func)
  local table = {}
  setmetatable(table, {
    __index = function(tbl, arg1)
      local ret = function(...)
        return func(arg1, ...)
      end
      tbl[arg1] = ret
      return ret
    end,
  })
  return table
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

--- @param after_each fun(name:string,block:fun())
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
