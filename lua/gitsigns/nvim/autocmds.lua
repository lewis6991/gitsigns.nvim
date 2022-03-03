if not vim.api.nvim_create_autocmd then
   return require('gitsigns.nvim.autocmds_compat')
end

local M = {}

function M.autocmd(event, opts)
   vim.api.nvim_create_autocmd(event, opts)
end

function M.augroup(name, opts)
   vim.api.nvim_create_augroup(name, opts or {})
end

return M
