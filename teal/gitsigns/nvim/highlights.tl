local v = vim.version()

if v.major == 0 and v.minor < 7 then
  return require('gitsigns.nvim.highlights_compat')
end

local M = {}

function M.highlight(group: string, opts: {string:any})
  vim.api.nvim_set_hl(0, group, opts)
end

return M
