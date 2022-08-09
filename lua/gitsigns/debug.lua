local M = {
   debug_mode = false,
   verbose = false,
   messages = {},
}

local function getvarvalue(name, lvl)
   lvl = lvl + 1
   local value
   local found


   local i = 1
   while true do
      local n, v = debug.getlocal(lvl, i)
      if not n then break end
      if n == name then
         value = v
         found = true
      end
      i = i + 1
   end
   if found then return value end


   local func = debug.getinfo(lvl).func
   i = 1
   while true do
      local n, v = debug.getupvalue(func, i)
      if not n then break end
      if n == name then return v end
      i = i + 1
   end


   return getfenv(func)[name]
end

local function get_context(lvl)
   lvl = lvl + 1
   local ret = {}
   ret.name = getvarvalue('__FUNC__', lvl)
   if not ret.name then
      local name0 = debug.getinfo(lvl, 'n').name or ''
      ret.name = name0:gsub('(.*)%d+$', '%1')
   end
   ret.bufnr = getvarvalue('bufnr', lvl) or
   getvarvalue('_bufnr', lvl) or
   getvarvalue('cbuf', lvl) or
   getvarvalue('buf', lvl)

   return ret
end



local function cprint(obj, lvl)
   lvl = lvl + 1
   local msg = type(obj) == "string" and obj or vim.inspect(obj)
   local ctx = get_context(lvl)
   local msg2
   if ctx.bufnr then
      msg2 = string.format('%s(%s): %s', ctx.name, ctx.bufnr, msg)
   else
      msg2 = string.format('%s: %s', ctx.name, msg)
   end
   table.insert(M.messages, msg2)
end

function M.dprint(obj)
   if not M.debug_mode then return end
   cprint(obj, 2)
end

function M.dprintf(obj, ...)
   if not M.debug_mode then return end
   cprint(obj:format(...), 2)
end

function M.vprint(obj)
   if not (M.debug_mode and M.verbose) then return end
   cprint(obj, 2)
end

function M.vprintf(obj, ...)
   if not (M.debug_mode and M.verbose) then return end
   cprint(obj:format(...), 2)
end

local function eprint(msg, level)
   local info = debug.getinfo(level + 2, 'Sl')
   if info then
      msg = string.format('(ERROR) %s(%d): %s', info.short_src, info.currentline, msg)
   end
   M.messages[#M.messages + 1] = msg
   if M.debug_mode then
      error(msg)
   end
end

function M.eprint(msg)
   eprint(msg, 1)
end

function M.eprintf(fmt, ...)
   eprint(fmt:format(...), 1)
end

local function process(raw_item, path)
   if path[#path] == vim.inspect.METATABLE then
      return nil
   elseif type(raw_item) == "function" then
      return nil
   elseif type(raw_item) == "table" then
      local key = path[#path]
      if key == 'compare_text' then
         local item = raw_item
         return { '...', length = #item, head = item[1] }
      elseif not vim.tbl_isempty(raw_item) and key == 'staged_diffs' then
         return { '...', length = #vim.tbl_keys(raw_item) }
      end
   end
   return raw_item
end

function M.add_debug_functions(cache)
   local R = {}
   R.dump_cache = function()
      local text = vim.inspect(cache, { process = process })
      vim.api.nvim_echo({ { text } }, false, {})
      return cache
   end

   R.debug_messages = function(noecho)
      if not noecho then
         for _, m in ipairs(M.messages) do
            vim.api.nvim_echo({ { m } }, false, {})
         end
      end
      return M.messages
   end

   R.clear_debug = function()
      M.messages = {}
   end

   return R
end

return M
