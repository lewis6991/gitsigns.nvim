local start_time = vim.loop.hrtime()

local M = {
  debug_mode = false,
  verbose = false,
  messages = {} --- @type [number, string, string, string][]
}

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

--- @param lvl integer
--- @return {name:string, bufnr: integer}
local function get_context(lvl)
  lvl = lvl + 1

  local name = getvarvalue('__FUNC__', lvl)
  if not name then
    local name0 = debug.getinfo(lvl, 'n').name or ''
    name = name0:gsub('(.*)%d+$', '%1')
  end

  local bufnr = getvarvalue('bufnr', lvl)
    or getvarvalue('_bufnr', lvl)
    or getvarvalue('cbuf', lvl)
    or getvarvalue('buf', lvl)

  return {name=name, bufnr=bufnr}
end

-- If called in a callback then make sure the callback defines a __FUNC__
-- variable which can be used to identify the name of the function.
--- @param kind string
--- @param obj any
--- @param lvl integer
local function cprint(kind, obj, lvl)
  lvl = lvl + 1
  --- @type string
  local msg = type(obj) == 'string' and obj or vim.inspect(obj)
  local ctx = get_context(lvl)
  local time = (vim.loop.hrtime() - start_time) / 1e6
  local ctx1 = ctx.name
  if ctx.bufnr then
    ctx1 = string.format('%s(%s)', ctx1, ctx.bufnr)
  end
  table.insert(M.messages, {time, kind, ctx1, msg})
end

function M.dprint(obj)
  if not M.debug_mode then
    return
  end
  cprint('debug', obj, 2)
end

function M.dprintf(obj, ...)
  if not M.debug_mode then
    return
  end
  cprint('debug', obj:format(...), 2)
end

function M.vprint(obj)
  if not (M.debug_mode and M.verbose) then
    return
  end
  cprint('info', obj, 2)
end

function M.vprintf(obj, ...)
  if not (M.debug_mode and M.verbose) then
    return
  end
  cprint('info', obj:format(...), 2)
end

local function eprint(msg, level)
  local info = debug.getinfo(level + 2, 'Sl')
  local ctx = info and string.format('%s<%d>', info.short_src, info.currentline) or '???'
  local time = (vim.loop.hrtime() - start_time) / 1e6
  table.insert(M.messages, { time, 'error', ctx, debug.traceback(msg) })
  if M.debug_mode then
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
--- @return [string,string][]
local function build_msg(m)
  local time, kind, ctx, msg = m[1], m[2], m[3], m[4]
  local hl = sev_to_hl[kind]
  return {
    { string.format('%.2f ', time), 'Comment' },
    { kind:upper():sub(1,1), hl },
    { string.format(' %s:', ctx), 'Tag'},
    { ' ' },
    { msg }
  }
end

function M.show()
  for _, m in ipairs(M.messages) do
    vim.api.nvim_echo(build_msg(m), false, {})
  end
end

--- @return string[]?
function M.get()
  local r = {} --- @type string[]
  for _, m in ipairs(M.messages) do
    local e = build_msg(m)
    local e1 = {} --- @type string[]
    for _, x in ipairs(e) do
      e1[#e1+1] = x[1]
    end
    r[#r+1] = table.concat(e1)
  end
  return r
end

return M
