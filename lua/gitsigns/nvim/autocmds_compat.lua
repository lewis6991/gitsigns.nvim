local cmd = vim.cmd

local M = {}

local callbacks = {}

function M._exec(id)
   callbacks[id]()
end

local function set_callback(fn)
   local id

   if jit then
      id = string.format("%p", fn)
   else
      id = tostring(fn):match('function: (.*)')
   end

   callbacks[id] = function() fn() end
   return string.format('lua require("gitsigns.nvim.autocmds_compat")._exec("%s")', id)
end

local function flatten(x)
   if type(x) == "table" then
      return table.concat(x, ",")
   else
      return x
   end
end

function M.autocmd(event, opts)
   cmd(table.concat({
      'autocmd',
      opts.group or '',
      flatten(event),
      opts.pattern and flatten(opts.pattern) or '*',
      opts.once and '++once' or '',
      opts.nested and '++nested' or '',
      type(opts.callback) == 'function' and set_callback(opts.callback) or opts.command,
   }, " "))
end

function M.augroup(name, opts)
   opts = opts or {}

   cmd("augroup " .. name)
   if opts.clear ~= false then
      cmd("autocmd!")
   end
   cmd("augroup END")
end

return M
