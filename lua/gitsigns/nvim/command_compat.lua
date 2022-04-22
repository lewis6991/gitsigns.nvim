local api = vim.api

local set_callback = require('gitsigns.nvim.callbacks').set

local M = {}

function M.command(name, fn, opts)
   vim.cmd(table.concat({
      'command' .. (opts.force and '!' or ''),
      opts.range and '-range',
      opts.nargs and '-nargs=' .. tostring(opts.nargs) or '',
      opts.complete and ('-complete=customlist,' .. set_callback(opts.complete, true)) or '',
      name,
      set_callback(function(range, line1, line2, args)
         fn({ range = range, line1 = line1, line2 = line2, args = args })
      end, false, '<range>, <line1>, <line2>, <q-args>'),
   }, ' '))
end

return M
