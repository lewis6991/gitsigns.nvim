local uv = vim.uv or vim.loop ---@diagnostic disable-line: deprecated

local is_win = vim.fn.has('win32') == 1

--- @class Gitsigns.Util.Path
local Path = {}

--- @class Gitsigns.Util
local M = {}

--- @param path? string
--- @return boolean
function Path.exists(path)
  return path ~= nil and uv.fs_stat(path) ~= nil
end

--- @param path string
--- @return boolean
function Path.is_dir(path)
  ---@diagnostic disable-next-line:param-type-mismatch
  local stat = uv.fs_lstat(path)
  if stat then
    return stat.type == 'directory'
  end
  return false
end

--- @async
--- @param path string
--- @return boolean
function Path.is_abs(path)
  -- Check if the path is absolute on Windows
  if is_win and M.cygpath(path):match('^%a:[/\\]') then
    return true
  end

  -- Check if the path is absolute on Unix-like systems
  return vim.startswith(path, '/')
end

function Path.join(...)
  if vim.fs.joinpath then
    return vim.fs.joinpath(...)
  end
  local path = table.concat({ ... }, '/')
  if is_win then
    path = path:gsub('\\', '/')
  end
  return (path:gsub('//+', '/'))
end

M.Path = Path

--- @param path string
--- @return string[]
function M.file_lines(path)
  local file = assert(io.open(path, 'rb'))
  local contents = file:read('*a')
  file:close()
  return vim.split(contents, '\n')
end

M.path_sep = package.config:sub(1, 1)

--- @param ... integer
--- @return string
local function make_bom(...)
  local r = {}
  ---@diagnostic disable-next-line:no-unknown
  for i, a in ipairs({ ... }) do
    ---@diagnostic disable-next-line:no-unknown
    r[i] = string.char(a)
  end
  return table.concat(r)
end

local BOM_TABLE = {
  ['utf-8'] = make_bom(0xef, 0xbb, 0xbf),
  ['utf-16le'] = make_bom(0xff, 0xfe),
  ['utf-16'] = make_bom(0xfe, 0xff),
  ['utf-16be'] = make_bom(0xfe, 0xff),
  ['utf-32le'] = make_bom(0xff, 0xfe, 0x00, 0x00),
  ['utf-32'] = make_bom(0xff, 0xfe, 0x00, 0x00),
  ['utf-32be'] = make_bom(0x00, 0x00, 0xfe, 0xff),
  ['utf-7'] = make_bom(0x2b, 0x2f, 0x76),
  ['utf-1'] = make_bom(0xf7, 0x54, 0x4c),
}

---@param x string?
---@param encoding string
---@return string?
local function add_bom(x, encoding)
  local bom = BOM_TABLE[encoding]
  if bom then
    return x and bom .. x or bom
  end
  return x
end

--- @param bufnr integer
--- @return string[]
function M.buf_lines(bufnr)
  -- nvim_buf_get_lines strips carriage returns if fileformat==dos
  local buftext = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  local dos = vim.bo[bufnr].fileformat == 'dos'

  if dos then
    for i = 1, #buftext - 1 do
      buftext[i] = buftext[i] .. '\r'
    end
  end

  if vim.bo[bufnr].endofline then
    -- Add CR to the last line
    if dos then
      buftext[#buftext] = buftext[#buftext] .. '\r'
    end
    buftext[#buftext + 1] = ''
  end

  if vim.bo[bufnr].bomb then
    buftext[1] = add_bom(buftext[1], vim.bo[bufnr].fileencoding)
  end

  return buftext
end

--- @param buf integer
local function delete_alt(buf)
  local alt = vim.api.nvim_buf_call(buf, function()
    return vim.fn.bufnr('#')
  end)
  if alt ~= buf and alt ~= -1 then
    pcall(vim.api.nvim_buf_delete, alt, { force = true })
  end
end

--- @param bufnr integer
--- @param name string
function M.buf_rename(bufnr, name)
  vim.api.nvim_buf_set_name(bufnr, name)
  delete_alt(bufnr)
end

--- @param events string[]
--- @param f fun()
function M.noautocmd(events, f)
  local ei = vim.o.eventignore
  vim.o.eventignore = table.concat(events, ',')
  f()
  vim.o.eventignore = ei
end

--- @param bufnr integer
--- @param start_row integer
--- @param end_row integer
--- @param lines string[]
function M.set_lines(bufnr, start_row, end_row, lines)
  if vim.bo[bufnr].fileformat == 'dos' then
    lines = M.strip_cr(lines)
  end
  if start_row == 0 and end_row == -1 then
    if lines[#lines] == '' then
      lines = vim.deepcopy(lines)
      lines[#lines] = nil
    else
      vim.bo[bufnr].eol = false
    end
  end
  vim.api.nvim_buf_set_lines(bufnr, start_row, end_row, false, lines)
end

--- @param time number
--- @param divisor integer
--- @param time_word string
--- @return string
local function to_relative_string(time, divisor, time_word)
  local num = math.floor(time / divisor)
  if num > 1 then
    time_word = time_word .. 's'
  end

  return num .. ' ' .. time_word .. ' ago'
end

--- @param timestamp number
--- @return string
function M.get_relative_time(timestamp)
  local current_timestamp = os.time()
  local elapsed = current_timestamp - timestamp

  if elapsed == 0 then
    return 'a while ago'
  end

  local minute_seconds = 60
  local hour_seconds = minute_seconds * 60
  local day_seconds = hour_seconds * 24
  local month_seconds = day_seconds * 30
  local year_seconds = month_seconds * 12

  if elapsed < minute_seconds then
    return to_relative_string(elapsed, 1, 'second')
  elseif elapsed < hour_seconds then
    return to_relative_string(elapsed, minute_seconds, 'minute')
  elseif elapsed < day_seconds then
    return to_relative_string(elapsed, hour_seconds, 'hour')
  elseif elapsed < month_seconds then
    return to_relative_string(elapsed, day_seconds, 'day')
  elseif elapsed < year_seconds then
    return to_relative_string(elapsed, month_seconds, 'month')
  else
    return to_relative_string(elapsed, year_seconds, 'year')
  end
end

--- @param opts vim.api.keyset.redraw
function M.redraw(opts)
  if vim.fn.has('nvim-0.10') == 1 then
    vim.api.nvim__redraw(opts)
  elseif opts.range then
    vim.api.nvim__buf_redraw_range(opts.buf or 0, opts.range[1], opts.range[2])
  end
end

--- @param xs string[]
--- @return boolean
local function is_dos(xs)
  -- Do not check CR at EOF
  for i = 1, #xs - 1 do
    local x = xs[i] --[[@as string]]
    if x:sub(-1) ~= '\r' then
      return false
    end
  end
  return true
end

--- Strip '\r' from the EOL of each line only if all lines end with '\r'
--- @param xs0 string[]
--- @return string[]
function M.strip_cr(xs0)
  if not is_dos(xs0) then
    -- don't strip, return early
    return xs0
  end

  -- all lines end with '\r', need to strip
  local xs = vim.deepcopy(xs0)
  for i = 1, #xs do
    local x = xs[i] --[[@as string]]
    xs[i] = x:sub(1, -2)
  end
  return xs
end

--- @param base? string
--- @return string?
function M.norm_base(base)
  if base == ':0' then
    return
  end
  if base and base:sub(1, 1):match('[~\\^]') then
    base = 'HEAD' .. base
  end
  return base
end

function M.emptytable()
  return setmetatable({}, {
    ---@param t table<any,any>
    ---@param k any
    ---@return any
    __index = function(t, k)
      t[k] = {}
      return t[k]
    end,
  })
end

local function expand_date(fmt, time)
  if fmt == '%R' then
    return M.get_relative_time(time)
  end
  return os.date(fmt, time)
end

---@param fmt string
---@param info table<string,any>
---@return string
function M.expand_format(fmt, info)
  local ret = {} --- @type string[]

  for _ = 1, 20 do -- loop protection
    -- Capture <name> or <name:format>
    local scol, ecol, match, key, time_fmt = fmt:find('(<([^:>]+):?([^>]*)>)')
    if not match then
      break
    end
    --- @cast scol -?
    --- @cast ecol -?
    --- @cast key string

    ret[#ret + 1], fmt = fmt:sub(1, scol - 1), fmt:sub(ecol + 1)

    local v = info[key]

    if v then
      if type(v) == 'table' then
        v = table.concat(v, '\n')
      end
      if vim.endswith(key, '_time') then
        if time_fmt == '' then
          time_fmt = '%Y-%m-%d'
        end
        v = expand_date(time_fmt, v)
      end
      match = tostring(v)
    end
    ret[#ret + 1] = match
  end

  ret[#ret + 1] = fmt
  return table.concat(ret, '')
end

--- @param buf string
--- @return boolean
function M.bufexists(buf)
  return vim.fn.bufexists(buf) == 1
end

--- @param x Gitsigns.BlameInfo
--- @return Gitsigns.BlameInfoPublic
function M.convert_blame_info(x)
  --- @type Gitsigns.BlameInfoPublic
  local ret = vim.tbl_extend('error', x, x.commit)
  ret.commit = nil
  return ret
end

--- Efficiently remove items from middle of a list a list.
---
--- Calling table.remove() in a loop will re-index the tail of the table on
--- every iteration, instead this function will re-index  the table exactly
--- once.
---
--- Based on https://stackoverflow.com/questions/12394841/safely-remove-items-from-an-array-table-while-iterating/53038524#53038524
---
---@param t any[]
---@param first integer
---@param last integer
function M.list_remove(t, first, last)
  local n = table.maxn(t)
  for i = 0, n - first do
    t[first + i] = t[last + 1 + i]
    t[last + 1 + i] = nil
  end
end

--- Efficiently insert items into the middle of a list.
---
--- Calling table.insert() in a loop will re-index the tail of the table on
--- every iteration, instead this function will re-index  the table exactly
--- once.
---
--- Based on https://stackoverflow.com/questions/12394841/safely-remove-items-from-an-array-table-while-iterating/53038524#53038524
---
---@param t any[]
---@param first integer
---@param last integer
---@param v any
function M.list_insert(t, first, last, v)
  local n = table.maxn(t)

  -- Shift table forward
  for i = n - first, 0, -1 do
    t[last + 1 + i] = t[first + i]
  end

  -- Fill in new values
  for i = first, last do
    t[i] = v
  end
end

--- Run a function once and ignore subsequent calls
--- @generic F: function
--- @param fn F
--- @return F
function M.once(fn)
  local called = false
  return function(...)
    if called then
      return
    end
    called = true
    return fn(...)
  end
end

--- @param x any
--- @return integer?
function M.tointeger(x)
  local nx = tonumber(x)
  if nx and nx == math.floor(nx) then
    --- @cast nx integer
    return nx
  end
end

local has_cygpath --- @type boolean?

--- @async
--- @param path string
--- @param mode? 'unix'|'windows' (default: 'windows')
--- @return string
function M.cygpath(path, mode)
  local async = require('gitsigns.async')
  local system = require('gitsigns.system').system

  if has_cygpath == nil then
    has_cygpath = is_win and vim.fn.executable('cygpath') == 1
  end

  if not has_cygpath or uv.fs_stat(path) then
    return path
  end

  -- If on windows and path isn't recognizable as a file, try passing it
  -- through cygpath
  --- @type string
  local stdout = async.await(3, system, {
    'cygpath',
    '--absolute',
    '--' .. (mode or 'windows'),
    path,
  }, { text = true }).stdout

  async.schedule()

  return assert(vim.split(stdout, '\n')[1])
end

--- Flattens a nested table structure into a flat array of strings. Only
--- traverses numeric keys, recursively flattening tables and collecting
--- strings.
--- @param x table<any,any> The input table to flatten.
--- @return string[] A flat array of strings extracted from the nested table.
function M.flatten(x)
  local ret = {} --- @type string[]
  for k, v in pairs(x) do
    if type(k) == 'number' then
      if type(v) == 'table' then
        vim.list_extend(ret, M.flatten(v))
      elseif type(v) == 'string' then
        ret[#ret + 1] = v
      end
    end
  end
  return ret
end

return M
