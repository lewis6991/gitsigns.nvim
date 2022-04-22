local api = vim.api

local set_callback = require('gitsigns.nvim.callbacks').set

local M = {}

function M.command(name: string, fn: function(api.UserCmdParams), opts: api.UserCmdOpts)
  vim.cmd(table.concat({
    'command'.. (opts.force and '!' or ''),
    opts.range and '-range',
    opts.nargs and '-nargs='..tostring(opts.nargs) or '',
    opts.complete and ('-complete=customlist,'..set_callback(opts.complete as function, true)) or '',
    name,
    set_callback(fn)
  }, ' '))
end

return M
