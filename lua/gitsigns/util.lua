local M = {}





function M.path_exists(path)
   return vim.loop.fs_stat(path) and true or false
end

local jit_os

if jit then
   jit_os = jit.os:lower()
end

local is_unix = false
if jit_os then
   is_unix = jit_os == 'linux' or jit_os == 'osx' or jit_os == 'bsd'
else
   local binfmt = package.cpath:match("%p[\\|/]?%p(%a+)")
   is_unix = binfmt ~= "dll"
end

function M.dirname(file)
   return file:match(string.format('^(.+)%s[^%s]+', M.path_sep, M.path_sep))
end

function M.file_lines(file)
   local text = {}
   for line in io.lines(file) do
      text[#text + 1] = line
   end
   return text
end

M.path_sep = package.config:sub(1, 1)

function M.buf_lines(bufnr)

   local buftext = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
   if vim.bo[bufnr].fileformat == 'dos' then
      for i = 1, #buftext do
         buftext[i] = buftext[i] .. '\r'
      end
   end
   return buftext
end

function M.set_lines(bufnr, start_row, end_row, lines)
   if vim.bo[bufnr].fileformat == 'dos' then
      for i = 1, #lines do
         lines[i] = lines[i]:gsub('\r$', '')
      end
   end
   vim.api.nvim_buf_set_lines(bufnr, start_row, end_row, false, lines)
end

function M.tmpname()
   if is_unix then
      return os.tmpname()
   end
   return vim.fn.tempname()
end

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

   local to_relative_string = function(time, divisor, time_word)
      local num = math.floor(time / divisor)
      if num > 1 then
         time_word = time_word .. 's'
      end

      return num .. ' ' .. time_word .. ' ago'
   end

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

function M.copy_array(x)
   local r = {}
   for i, e in ipairs(x) do
      r[i] = e
   end
   return r
end


function M.strip_cr(xs0)
   for i = 1, #xs0 do
      if xs0[i]:sub(-1) ~= '\r' then

         return xs0
      end
   end

   local xs = vim.deepcopy(xs0)
   for i = 1, #xs do
      xs[i] = xs[i]:sub(1, -2)
   end
   return xs
end

function M.calc_base(base)
   if base and base:sub(1, 1):match('[~\\^]') then
      base = 'HEAD' .. base
   end
   return base
end

function M.emptytable()
   return setmetatable({}, {
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


function M.expand_format(fmt, info, reltime)
   local ret = {}

   for _ = 1, 20 do

      local scol, ecol, match, key, time_fmt = fmt:find('(<([^:>]+):?([^>]*)>)')
      if not match then
         break
      end

      ret[#ret + 1], fmt = fmt:sub(1, scol - 1), fmt:sub(ecol + 1)

      local v = info[key]

      if v then
         if type(v) == "table" then
            v = table.concat(v, '\n')
         end
         if vim.endswith(key, '_time') then
            if time_fmt == '' then
               time_fmt = reltime and '%R' or '%Y-%m-%d'
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

return M
