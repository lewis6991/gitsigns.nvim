if not vim.api.nvim_create_user_command then
   return require('gitsigns.nvim.command_compat')
end

local api = vim.api

local M = {}

function M.command(name, fn, opts)
   api.nvim_create_user_command(name, fn, opts)
end

return M
