require('vim.compat')
local shared = require('vim.shared')
local assert = require('luassert')
local luv = require('luv')

assert:set_parameter('TableFormatLevel', 100)

local quote_me = '[^.%w%+%-%@%_%/]' -- complement (needn't quote)
local function shell_quote(str)
  if string.find(str, quote_me) or str == '' then
    return '"' .. str:gsub('[$%%"\\]', '\\%0') .. '"'
  else
    return str
  end
end

local module = {}

function module.argss_to_cmd(...)
  local cmd = ''
  for i = 1, select('#', ...) do
    local arg = select(i, ...)
    if type(arg) == 'string' then
      cmd = cmd .. ' ' ..shell_quote(arg)
    else
      for _, subarg in ipairs(arg) do
        cmd = cmd .. ' ' .. shell_quote(subarg)
      end
    end
  end
  return cmd
end

function module.popen_r(...)
  return io.popen(module.argss_to_cmd(...), 'r')
end

-- sleeps the test runner (_not_ the nvim instance)
function module.sleep(ms)
  luv.sleep(ms*6)
end

module.eq = assert.are.same
module.neq = assert.are_not.same
module.ok = assert.is_true

function module.matches(pat, actual)
  if nil ~= string.match(actual, pat) then
    return true
  end
  error(string.format('Pattern does not match.\nPattern:\n%s\nActual:\n%s', pat, actual))
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
function module.pcall_err_withfile(fn, ...)
  assert(type(fn) == 'function')
  local status, rv = pcall(fn, ...)
  if status == true then
    error('expected failure, but got success')
  end
  -- From:
  --    C:/long/path/foo.lua:186: Expected string, got number
  -- to:
  --    .../foo.lua:0: Expected string, got number
  local errmsg = tostring(rv):gsub('([%s<])vim[/\\]([^%s:/\\]+):%d+', '%1\xffvim\xff%2:0')
                             :gsub('[^%s<]-[/\\]([^%s:/\\]+):%d+', '.../%1:0')
                             :gsub('\xffvim\xff', 'vim/')
  return errmsg
end

function module.pcall_err(fn, ...)
  local errmsg = module.pcall_err_withfile(fn, ...)

  return errmsg:gsub('.../helpers.lua:0: ', '')
end

module.uname = (function()
  local platform = nil
  return (function()
    if platform then
      return platform
    end

    local status, f = pcall(module.popen_r, 'uname', '-s')
    if status then
      platform = string.lower(f:read("*l"))
      f:close()
    else
      error('unknown platform')
    end
    return platform
  end)
end)()

local function tmpdir_get()
  return os.getenv('TMPDIR') and os.getenv('TMPDIR') or os.getenv('TEMP')
end

-- Is temp directory `dir` defined local to the project workspace?
local function tmpdir_is_local(dir)
  return not not (dir and string.find(dir, 'Xtest'))
end

module.tmpname = (function()
  local seq = 0
  local tmpdir = tmpdir_get()
  return (function()
    if tmpdir_is_local(tmpdir) then
      -- Cannot control os.tmpname() dir, so hack our own tmpname() impl.
      seq = seq + 1
      local fname = tmpdir..'/nvim-test-lua-'..seq
      io.open(fname, 'w'):close()
      return fname
    else
      local fname = os.tmpname()
      if fname:match('^/tmp') and module.uname() == 'darwin' then
        -- In OS X /tmp links to /private/tmp
        return '/private'..fname
      else
        return fname
      end
    end
  end)
end)()

-- Concat list-like tables.
function module.concat_tables(...)
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

function module.dedent(str, leave_indent)
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

module = shared.tbl_extend('error', module, shared)


require('coxpcall')
local lfs = require('lfs')

-- nvim client: Found in .deps/usr/share/lua/<version>/nvim/ if "bundled".
local Session = require('nvim.session')
local ChildProcessStream = require('nvim.child_process_stream')


module.nvim_prog = os.getenv('NVIM_PRG')

-- Default settings for the test session.
module.nvim_set = (
  'set shortmess+=IS background=light noswapfile noautoindent startofline'
  ..' laststatus=1 undodir=. directory=. viewdir=. backupdir=.'
  ..' belloff= wildoptions-=pum noshowcmd noruler nomore redrawdebug=invalid')
module.nvim_argv = {
  module.nvim_prog, '-u', 'NONE', '-i', 'NONE',
  '--cmd', module.nvim_set, '--embed'}
-- Directory containing nvim.
module.nvim_dir = module.nvim_prog:gsub("[/\\][^/\\]+$", "")
if module.nvim_dir == module.nvim_prog then
  module.nvim_dir = "."
end

local session, loop_running, last_error, method_error

function module.get_session()
  return session
end

function module.set_session(s, keep)
  if session and not keep then
    session:close()
  end
  session = s
end

function module.request(method, ...)
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

function module.next_msg(timeout)
  return session:next_message(timeout and timeout or 10000)
end


local function call_and_stop_on_error(lsession, ...)
  local status, result = copcall(...)  -- luacheck: ignore
  if not status then
    lsession:stop()
    last_error = result
    return ''
  end
  return result
end

function module.set_method_error(err)
  method_error = err
end

function module.run_session(lsession, request_cb, notification_cb, setup_cb, timeout)
  local on_request, on_notification, on_setup

  if request_cb then
    function on_request(method, args)
      method_error = nil
      local result = call_and_stop_on_error(lsession, request_cb, method, args)
      if method_error ~= nil then
        return method_error, true
      end
      return result
    end
  end

  if notification_cb then
    function on_notification(method, args)
      call_and_stop_on_error(lsession, notification_cb, method, args)
    end
  end

  if setup_cb then
    function on_setup()
      call_and_stop_on_error(lsession, setup_cb)
    end
  end

  loop_running = true
  session:run(on_request, on_notification, on_setup, timeout)
  loop_running = false
  if last_error then
    local err = last_error
    last_error = nil
    error(err)
  end
end

function module.run(request_cb, notification_cb, setup_cb, timeout)
  module.run_session(session, request_cb, notification_cb, setup_cb, timeout)
end

function module.stop()
  session:stop()
end

-- Executes an ex-command. VimL errors manifest as client (lua) errors, but
-- v:errmsg will not be updated.
function module.command(cmd)
  module.request('nvim_command', cmd)
end

-- Evaluates a VimL expression.
-- Fails on VimL error, but does not update v:errmsg.
function module.eval(expr)
  return module.request('nvim_eval', expr)
end

-- Executes a VimL function.
-- Fails on VimL error, but does not update v:errmsg.
function module.call(name, ...)
  return module.request('nvim_call_function', name, {...})
end

-- Sends user input to Nvim.
-- Does not fail on VimL error, but v:errmsg will be updated.
local function nvim_feed(input)
  while #input > 0 do
    local written = module.request('nvim_input', input)
    if written == nil then
      module.assert_alive()
      error('crash? (nvim_input returned nil)')
    end
    input = input:sub(written + 1)
  end
end

function module.feed(...)
  for _, v in ipairs({...}) do
    nvim_feed(module.dedent(v))
  end
end

function module.rawfeed(...)
  for _, v in ipairs({...}) do
    nvim_feed(module.dedent(v))
  end
end

function module.merge_args(...)
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
--  "-u", "-i", "--cmd" are treated specially: their "values" are also removed.
--  Example:
--      args={'--headless', '-u', 'NONE'}
--      args_rm={'--cmd', '-u'}
--  Result:
--      {'--headless'}
--
--  All cases are removed.
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
    if module.tbl_contains(skip_following, last) then
      last = ''
    elseif module.tbl_contains(args_rm, arg) then
      last = arg
    else
      table.insert(new_args, arg)
    end
  end
  return new_args
end

function module.spawn(argv, env)
  local child_stream = ChildProcessStream.spawn(argv, env)
  return Session.new(child_stream)
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
function module.clear(...)
  local argv, env = module.new_argv(...)
  module.set_session(module.spawn(argv, env))
end

-- Builds an argument list for use in clear().
--
--@see clear() for parameters.
function module.new_argv(...)
  local args = {unpack(module.nvim_argv)}
  table.insert(args, '--headless')
  local new_args
  local env = nil
  local opts = select(1, ...)
  if type(opts) == 'table' then
    args = remove_args(args, opts.args_rm)
    if opts.env then
      local env_tbl = {}
      for k, v in pairs(opts.env) do
        assert(type(k) == 'string')
        assert(type(v) == 'string')
        env_tbl[k] = v
      end
      for _, k in ipairs({
        'HOME',
        'LD_LIBRARY_PATH',
        'PATH',
        'NVIM_RPLUGIN_MANIFEST',
        'XDG_DATA_DIRS',
        'TMPDIR',
      }) do
        if not env_tbl[k] then
          env_tbl[k] = os.getenv(k)
        end
      end
      env = {}
      for k, v in pairs(env_tbl) do
        env[#env + 1] = k .. '=' .. v
      end
    end
    new_args = opts.args or {}
  else
    new_args = {...}
  end
  for _, arg in ipairs(new_args) do
    table.insert(args, arg)
  end
  return args, env
end

function module.insert(...)
  nvim_feed('i')
  for _, v in ipairs({...}) do
    local escaped = v:gsub('<', '<lt>')
    module.rawfeed(escaped)
  end
  nvim_feed('<ESC>')
end

-- Executes an ex-command by user input. Because nvim_input() is used, VimL
-- errors will not manifest as client (lua) errors. Use command() for that.
function module.feed_command(...)
  for _, v in ipairs({...}) do
    if v:sub(1, 1) ~= '/' then
      -- not a search command, prefix with colon
      nvim_feed(':')
    end
    nvim_feed(v:gsub('<', '<lt>'))
    nvim_feed('<CR>')
  end
end

local sourced_fnames = {}
function module.source(code)
  local fname = module.tmpname()
  module.write_file(fname, code)
  module.command('source '..fname)
  -- DO NOT REMOVE FILE HERE.
  -- do_source() has a habit of checking whether files are “same” by using inode
  -- and device IDs. If you run two source() calls in quick succession there is
  -- a good chance that underlying filesystem will reuse the inode, making files
  -- appear as “symlinks” to do_source when it checks FileIDs. With current
  -- setup linux machines (both QB, travis and mine(ZyX-I) with XFS) do reuse
  -- inodes, Mac OS machines (again, both QB and travis) do not.
  --
  -- Files appearing as “symlinks” mean that both the first and the second
  -- source() calls will use same SID, which may fail some tests which check for
  -- exact numbers after `<SNR>` in e.g. function names.
  sourced_fnames[#sourced_fnames + 1] = fname
  return fname
end

function module.nvim(method, ...)
  return module.request('nvim_'..method, ...)
end

function module.nvim_async(method, ...)
  session:notify('nvim_'..method, ...)
end

function module.buffer(method, ...)
  return module.request('nvim_buf_'..method, ...)
end

function module.window(method, ...)
  return module.request('nvim_win_'..method, ...)
end

function module.curbuf(method, ...)
  if not method then
    return module.nvim('get_current_buf')
  end
  return module.buffer(method, 0, ...)
end

function module.poke_eventloop()
  -- Execute 'nvim_eval' (a deferred function) to
  -- force at least one main_loop iteration
  session:request('nvim_eval', '1')
end

function module.buf_lines(bufnr)
  return module.exec_lua("return vim.api.nvim_buf_get_lines((...), 0, -1, false)", bufnr)
end

--@see buf_lines()
function module.curbuf_contents()
  module.poke_eventloop()  -- Before inspecting the buffer, do whatever.
  return table.concat(module.curbuf('get_lines', 0, -1, true), '\n')
end

function module.curwin(method, ...)
  if not method then
    return module.nvim('get_current_win')
  end
  return module.window(method, 0, ...)
end

function module.expect(contents)
  return module.eq(module.dedent(contents), module.curbuf_contents())
end

-- Checks that the Nvim session did not terminate.
function module.assert_alive()
  assert(2 == module.eval('1+1'), 'crash? request failed')
end

local function do_rmdir(path)
  local mode, errmsg, errcode = lfs.attributes(path, 'mode')
  if mode == nil then
    if errcode == 2 then
      -- "No such file or directory", don't complain.
      return
    end
    error(string.format('rmdir: %s (%d)', errmsg, errcode))
  end
  if mode ~= 'directory' then
    error(string.format('rmdir: not a directory: %s', path))
  end
  for file in lfs.dir(path) do
    if file ~= '.' and file ~= '..' then
      local abspath = path..'/'..file
      if lfs.attributes(abspath, 'mode') == 'directory' then
        do_rmdir(abspath)  -- recurse
      else
        local ret, err = os.remove(abspath)
        if not ret then
          if not session then
            error('os.remove: '..err)
          else
            -- Try Nvim delete(): it handles `readonly` attribute on Windows,
            -- and avoids Lua cross-version/platform incompatibilities.
            if -1 == module.call('delete', abspath) then
              error('delete() failed: '..abspath)
            end
          end
        end
      end
    end
  end
  local ret, err = lfs.rmdir(path)
  if not ret then
    error('lfs.rmdir('..path..'): '..err)
  end
end

function module.rmdir(path)
  local ret, _ = pcall(do_rmdir, path)
  -- During teardown, the nvim process may not exit quickly enough, then rmdir()
  -- will fail (on Windows).
  if not ret then  -- Try again.
    module.sleep(1000)
    do_rmdir(path)
  end
end

function module.exc_exec(cmd)
  module.command(([[
    try
      execute "%s"
    catch
      let g:__exception = v:exception
    endtry
  ]]):format(cmd:gsub('\n', '\\n'):gsub('[\\"]', '\\%0')))
  local ret = module.eval('get(g:, "__exception", 0)')
  module.command('unlet! g:__exception')
  return ret
end

function module.create_callindex(func)
  local table = {}
  setmetatable(table, {
    __index = function(tbl, arg1)
      local ret = function(...) return func(arg1, ...) end
      tbl[arg1] = ret
      return ret
    end,
  })
  return table
end

module.funcs = module.create_callindex(module.call)
module.meths = module.create_callindex(module.nvim)
module.async_meths = module.create_callindex(module.nvim_async)
module.bufmeths = module.create_callindex(module.buffer)
module.winmeths = module.create_callindex(module.window)
module.curbufmeths = module.create_callindex(module.curbuf)
module.curwinmeths = module.create_callindex(module.curwin)

function module.exec(code)
  return module.meths.exec(code, false)
end

function module.exec_capture(code)
  return module.meths.exec(code, true)
end

function module.exec_lua(code, ...)
  return module.meths.exec_lua(code, {...})
end

function module.redir_exec(cmd)
  module.meths.set_var('__redir_exec_cmd', cmd)
  module.command([[
    redir => g:__redir_exec_output
      silent! execute g:__redir_exec_cmd
    redir END
  ]])
  local ret = module.meths.get_var('__redir_exec_output')
  module.meths.del_var('__redir_exec_output')
  module.meths.del_var('__redir_exec_cmd')
  return ret
end

return function(after_each)
  if after_each then
    after_each(function()
      for _, fname in ipairs(sourced_fnames) do
        os.remove(fname)
      end
      if session then
        local msg = session:next_message(0)
        if msg then
          if msg[1] == "notification" and msg[2] == "nvim_error_event" then
            error(msg[3][2])
          end
        end
      end
    end)
  end
  return module
end
