local uv = vim.uv or vim.loop ---@diagnostic disable-line: deprecated

local start_time = uv.hrtime()

--- @class Gitsigns.log
--- @field package messages [number, string, string, string][]
local M = {
  messages = {},
}

function M.debug_mode()
  return require('gitsigns.config').config.debug_mode
end

function M.verbose()
  return require('gitsigns.config').config._verbose
end

--- @param name string
--- @param lvl integer
--- @return any
local function getvarvalue(name, lvl)
  lvl = lvl + 1
  local value --- @type any?
  local found --- @type boolean?

  -- try local variables
  local i = 1
  while true do
    local n, v = debug.getlocal(lvl, i)
    if not n then
      break
    end
    if n == name then
      value = v
      found = true
    end
    i = i + 1
  end
  if found then
    return value
  end

  -- try upvalues
  local func = debug.getinfo(lvl).func
  i = 1
  while true do
    local n, v = debug.getupvalue(func, i)
    if not n then
      break
    end
    if n == name then
      return v
    end
    i = i + 1
  end

  -- not found; get global
  return getfenv(func)[name]
end

--- @param info debuglib.DebugInfo
--- @return string
local function get_cur_module(info)
  local src = info.source or '???'

  if vim.startswith(src, '@') then
    src = src:sub(2)
  end
  src = src:gsub('^%./', '')

  local rel = src:match('^lua/(.+)$') or src:match('[/\\]lua[/\\](.+)$')
  local module = (rel or src):gsub('%.lua$', ''):gsub('/init$', ''):gsub('[\\/]', '.')
  return module
end

--- @param tbl table
--- @param func function
--- @return string?
local function find_func_name(tbl, func)
  for k, v in pairs(tbl) do
    if v == func and type(k) == 'string' then
      return k
    end
  end
end

--- @param func function?
--- @param lvl integer
--- @return string?
local function get_cur_func_name_from_self(func, lvl)
  if not func then
    return
  end

  local self_tbl = getvarvalue('self', lvl)
  if type(self_tbl) ~= 'table' then
    return
  end

  local name = find_func_name(self_tbl, func)
  if name then
    return name
  end

  local mt = getmetatable(self_tbl)
  local idx = mt and mt.__index
  if type(idx) ~= 'table' then
    return
  end

  local name1 = find_func_name(idx, func)
  if name1 then
    return name1
  end
end

--- @param func function?
--- @param module string?
--- @return string?
local function get_cur_func_name_from_loaded(func, module)
  if not func then
    return
  end
  local tbl = package.loaded[module]
  if type(tbl) == 'table' then
    return find_func_name(tbl, func)
  end
end

local func_names_cache = {} --- @type table<function, string>

--- @param info debuglib.DebugInfo
--- @param lvl integer
--- @param module string?
--- @return string
local function get_cur_func_name(info, lvl, module)
  lvl = lvl + 1

  local func = info.func

  if func_names_cache[func] then
    return func_names_cache[func]
  end

  local name = getvarvalue('__FUNC__', lvl) --[[@as string?]]
    or info.name
    or get_cur_func_name_from_self(func, lvl)
    or get_cur_func_name_from_loaded(func, module)
    or (info.what == 'main') and 'main'
    or ('<anonymous@%d>'):format(info.linedefined or 0)

  func_names_cache[func] = name

  return name
end

--- @param lvl integer
--- @return {module: string?, name:string, bufnr: integer}
local function get_context(lvl)
  lvl = lvl + 1
  local info = debug.getinfo(lvl, 'nSf') or {} --- @type any
  local module = get_cur_module(info)
  local func = get_cur_func_name(info, lvl, module)

  module = module:gsub('^gitsigns%.', '')

  func = func:gsub('(.*)%d+$', '%1')

  local bufnr = getvarvalue('bufnr', lvl)
    or getvarvalue('_bufnr', lvl)
    or getvarvalue('cbuf', lvl)
    or getvarvalue('buf', lvl)

  return { module = module, name = func, bufnr = bufnr }
end

local function tostring(obj)
  return type(obj) == 'string' and obj or vim.inspect(obj)
end

--- If called in a callback then make sure the callback defines a __FUNC__
--- variable which can be used to identify the name of the function.
--- @param kind string
--- @param lvl integer
--- @param ... any
local function cprint(kind, lvl, ...)
  lvl = lvl + 1
  local msgs = {} --- @type string[]
  for i = 1, select('#', ...) do
    msgs[i] = tostring(select(i, ...))
  end
  local msg = table.concat(msgs, ' ')
  local ctx = get_context(lvl)
  local time = (uv.hrtime() - start_time) / 1e6
  local ctx1 = ctx.module and ctx.module .. '.' .. ctx.name or ctx.name
  if ctx.bufnr then
    ctx1 = string.format('%s(%s)', ctx1, ctx.bufnr)
  end
  table.insert(M.messages, { time, kind, ctx1, msg })
end

function M.dprint(...)
  if not M.debug_mode() then
    return
  end
  cprint('debug', 2, ...)
end

function M.dprintf(obj, ...)
  if not M.debug_mode() then
    return
  end
  cprint('debug', 2, obj:format(...))
end

function M.vprint(...)
  if not (M.debug_mode() and M.verbose()) then
    return
  end
  cprint('info', 2, ...)
end

function M.vprintf(obj, ...)
  if not (M.debug_mode() and M.verbose()) then
    return
  end
  cprint('info', 2, obj:format(...))
end

--- @param msg string
--- @param level integer
local function eprint(msg, level)
  local info = debug.getinfo(level + 2, 'Sl')
  local ctx = info and string.format('%s<%d>', info.short_src, info.currentline) or '???'
  local time = (uv.hrtime() - start_time) / 1e6
  table.insert(M.messages, { time, 'error', ctx, debug.traceback(msg) })
  if M.debug_mode() then
    error(msg, 3)
  end
end

function M.eprint(msg)
  eprint(msg, 1)
end

function M.eprintf(fmt, ...)
  eprint(fmt:format(...), 1)
end

--- @param cond boolean
--- @param msg string
--- @return boolean
function M.assert(cond, msg)
  if not cond then
    eprint(msg, 1)
  end

  return not cond
end

local sev_to_hl = {
  debug = 'Title',
  info = 'MoreMsg',
  warn = 'WarningMsg',
  error = 'ErrorMsg',
}

function M.clear()
  M.messages = {}
end

--- @param m [number, string, string, string]
--- @param verbose? boolean
--- @return [string,string?][]
local function build_msg(m, verbose)
  local time, kind, ctx, msg = m[1], m[2], m[3], m[4]
  local hl = sev_to_hl[kind]

  -- Scrub some messages
  if not verbose and ctx == 'run_job' then
    ctx = 'git'
    msg = msg
      :gsub(vim.pesc('--no-pager --no-optional-locks --literal-pathspecs -c gc.auto=0 '), '')
      :gsub(vim.pesc('-c core.quotepath=off'), '')

    local cwd = vim.uv.cwd()
    if cwd then
      msg = msg:gsub(vim.pesc(cwd), '$CWD')
    end

    local home = vim.env.HOME
    if home then
      msg = msg:gsub(vim.pesc(home), '$HOME')
    end
  end

  return {
    { string.format('%.2f ', time), 'Comment' },
    { kind:upper():sub(1, 1), hl },
    { string.format(' %s:', ctx), 'Tag' },
    { ' ' },
    { msg },
  }
end

function M.show()
  local lastm --- @type number?
  for _, m in ipairs(M.messages) do
    if lastm and m[1] - lastm > 200 then
      vim.api.nvim_echo({ { '|', 'NonText' } }, false, {})
    end
    lastm = m[1]
    vim.api.nvim_echo(build_msg(m), false, {})
  end
end

--- @param verbose? boolean
--- @return string[]?
function M.get(verbose)
  local r = {} --- @type string[]
  for _, m in ipairs(M.messages) do
    local e = build_msg(m, verbose)
    local e1 = {} --- @type string[]
    for _, x in ipairs(e) do
      e1[#e1 + 1] = x[1]
    end
    r[#r + 1] = table.concat(e1)
  end
  return r
end

return M
