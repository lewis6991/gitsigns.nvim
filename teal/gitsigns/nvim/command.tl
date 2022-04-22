if not vim.api.nvim_create_user_command then
  return require('gitsigns.nvim.command_compat')
end

local api = vim.api

local M = {}

function M.command(name: string, fn: function(api.UserCmdParams), opts: api.UserCmdOpts)
  api.nvim_create_user_command(name, fn, opts)
end

return M
