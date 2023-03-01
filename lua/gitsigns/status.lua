local api = vim.api


local StatusObj = {}








local Status = {
   StatusObj = StatusObj,
}

function Status:update(bufnr, status)
   if not api.nvim_buf_is_loaded(bufnr) then
      return
   end
   local bstatus = vim.b[bufnr].gitsigns_status_dict
   if bstatus then
      status = vim.tbl_extend('force', bstatus, status)
   end
   vim.b[bufnr].gitsigns_head = status.head or ''
   vim.b[bufnr].gitsigns_status_dict = status

   local config = require('gitsigns.config').config

   vim.b[bufnr].gitsigns_status = config.status_formatter(status)
end

function Status:clear(bufnr)
   if not api.nvim_buf_is_loaded(bufnr) then
      return
   end
   vim.b[bufnr].gitsigns_head = nil
   vim.b[bufnr].gitsigns_status_dict = nil
   vim.b[bufnr].gitsigns_status = nil
end

function Status:clear_diff(bufnr)
   self:update(bufnr, { added = 0, removed = 0, changed = 0 })
end

return Status
