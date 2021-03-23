require('gitsigns/types')
local api = vim.api

local Status = {
   status = {},
   formatter = nil,
}

function Status:update(bufnr, status)
   if not api.nvim_buf_is_loaded(bufnr) then
      return
   end
   if status then
      self.status = status
   end
   api.nvim_buf_set_var(bufnr, 'gitsigns_head', self.status.head or '')
   api.nvim_buf_set_var(bufnr, 'gitsigns_status_dict', self.status)
   api.nvim_buf_set_var(bufnr, 'gitsigns_status', self.formatter(self.status))
end

function Status:clear(bufnr)
   if not api.nvim_buf_is_loaded(bufnr) then
      return
   end
   api.nvim_buf_del_var(bufnr, 'gitsigns_head')
   api.nvim_buf_del_var(bufnr, 'gitsigns_status_dict')
   api.nvim_buf_del_var(bufnr, 'gitsigns_status')
end

function Status:update_head(bufnr, head)
   self.status.head = head
   Status:update(bufnr)
end

return Status
