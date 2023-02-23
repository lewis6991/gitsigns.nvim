local api = vim.api


local record StatusObj
  added   : integer
  removed : integer
  changed : integer
  head    : string
  root    : string
  gitdir  : string
end

local Status = {
  StatusObj = StatusObj,
}

function Status:update(bufnr: integer, status: StatusObj)
  if not api.nvim_buf_is_loaded(bufnr) then
    return
  end
  local bstatus = vim.b[bufnr].gitsigns_status_dict
  if bstatus then
    status = vim.tbl_extend('force', bstatus as table, status as table) as StatusObj
  end
  vim.b[bufnr].gitsigns_head = status.head or ''
  vim.b[bufnr].gitsigns_status_dict = status

  local config = require('gitsigns.config').config

  vim.b[bufnr].gitsigns_status = config.status_formatter(status)
end

function Status:clear(bufnr: integer)
  if not api.nvim_buf_is_loaded(bufnr) then
    return
  end
  vim.b[bufnr].gitsigns_head = nil
  vim.b[bufnr].gitsigns_status_dict = nil
  vim.b[bufnr].gitsigns_status = nil
end

function Status:clear_diff(bufnr: integer)
  self:update(bufnr, { added = 0, removed = 0, changed = 0 })
end

return Status
