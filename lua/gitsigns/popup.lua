local popup = {}

local api = vim.api

function popup.create(what, opts)
  local bufnr = api.nvim_create_buf(false, true)
  assert(bufnr, "Failed to create buffer")

  api.nvim_buf_set_lines(bufnr, 0, -1, true, what)

  local width
  if opts.width then
    width = opts.width
  else
    width = 0
    for _, l in pairs(what) do
      if #l > width then
        width = #l
      end
    end
  end

  opts = opts or {}

  local win_id = api.nvim_open_win(bufnr, false, {
    relative = opts.relative,
    row      = opts.row or 0,
    col      = opts.col or 0,
    height   = opts.height or #what,
    width    = width
  })

  vim.lsp.util.close_preview_autocmd({'CursorMoved', 'CursorMovedI'}, win_id)

  if opts.highlight then
    api.nvim_win_set_option(win_id, 'winhl', string.format('Normal:%s', opts.highlight))
  end

  return win_id, bufnr
end

return popup
