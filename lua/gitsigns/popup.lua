local popup = {}

local api = vim.api

function popup.create(what, vim_options)
  local bufnr = api.nvim_create_buf(false, true)
  assert(bufnr, "Failed to create buffer")

  api.nvim_buf_set_lines(bufnr, 0, -1, true, what)

  local width = 0
  for _, l in pairs(what) do
    if #l > width then
      width = #l
    end
  end

  local win_id = api.nvim_open_win(bufnr, false, {
    relative = vim_options.relative,
    row = 0,
    col = 0,
    height = #what,
    width = width
  })

  vim.lsp.util.close_preview_autocmd({'CursorMoved', 'CursorMovedI'}, win_id)

  if vim_options.highlight then
    api.nvim_win_set_option(win_id, 'winhl', string.format('Normal:%s', vim_options.highlight))
  end

  return win_id, bufnr
end

return popup
