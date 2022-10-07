if not vim.api.nvim_create_autocmd then
  return require('gitsigns.nvim.autocmds_compat')
end

local M = {}

function M.autocmd(event: string|{string}, opts: vim.api.AutoCmdOpts)
  vim.api.nvim_create_autocmd(event, opts)
end

function M.augroup(name: string, opts: vim.api.AugroupOpts)
  vim.api.nvim_create_augroup(name, opts or {})
end

function M.doautocmd(event: string|{string}, opts: vim.api.ExecAutoCmdOpts)
  vim.api.nvim_exec_autocmds(event, opts or {})
end

return M
