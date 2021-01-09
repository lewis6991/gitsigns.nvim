local api = vim.api

local Status = {
  status = {},
  formatter = nil
}

function Status:update(bufnr, status)
  if status then
    self.status = status
  end
  vim.schedule(function()
    api.nvim_buf_set_var(bufnr, 'gitsigns_head', self.status.head or '')
    api.nvim_buf_set_var(bufnr, 'gitsigns_status_dict', self.status)
    api.nvim_buf_set_var(bufnr, 'gitsigns_status', self.formatter(self.status))
  end)
end

function Status:update_head(bufnr, head)
  self.status.head = head
  Status:update(bufnr)
end

return Status
