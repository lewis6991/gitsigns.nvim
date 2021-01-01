local api = vim.api

local Status = {
  laststatus = {},
  formatter = nil
}

function Status:update_vars(bufnr, status)
  vim.schedule(function()
    api.nvim_buf_set_var(bufnr, 'gitsigns_head', status.head or '')
    api.nvim_buf_set_var(bufnr, 'gitsigns_status_dict', status)
    api.nvim_buf_set_var(bufnr, 'gitsigns_status', self.formatter(status))
  end)
  self.laststatus = status
end

function Status:update_head_var(bufnr, head)
  local status = self.laststatus
  status.head = head
  Status:update_vars(bufnr, status)
end

return Status
