local api = vim.api

local StatusObj = {}








local Status = {
   StatusObj = StatusObj,
   formatter = nil,
}

function Status:update(bufnr, status)
   if not api.nvim_buf_is_loaded(bufnr) then
      return
   end
   local has_bstatus, bstatus = pcall(api.nvim_buf_get_var, bufnr, 'gitsigns_status_dict')
   if has_bstatus then
      status = vim.tbl_extend('force', bstatus, status)
   end
   api.nvim_buf_set_var(bufnr, 'gitsigns_head', status.head or '')
   api.nvim_buf_set_var(bufnr, 'gitsigns_status_dict', status)
   api.nvim_buf_set_var(bufnr, 'gitsigns_status', self.formatter(status))
end

function Status:clear(bufnr)
   if not api.nvim_buf_is_loaded(bufnr) then
      return
   end
   api.nvim_buf_del_var(bufnr, 'gitsigns_head')
   api.nvim_buf_del_var(bufnr, 'gitsigns_status_dict')
   api.nvim_buf_del_var(bufnr, 'gitsigns_status')
end

function Status:clear_diff(bufnr)
   self:update(bufnr, { added = 0, removed = 0, changed = 0 })
end

return Status
