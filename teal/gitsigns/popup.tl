local popup = {}

local api = vim.api

local function bufnr_calc_width(buf: integer, lines: {string}): integer
  return api.nvim_buf_call(buf, function(): integer
    local width = 0
    for _, l in ipairs(lines) do
      local len = vim.fn.strdisplaywidth(l)
      if len > width then
        width = len
      end
    end
    return width + 1 -- Add 1 for some miinor padding
  end)
end

function popup.create(lines: {string}, opts: {string:any}): number, number
  local ts = api.nvim_buf_get_option(0, 'tabstop')
  local bufnr = api.nvim_create_buf(false, true)
  assert(bufnr, "Failed to create buffer")

  -- In case nvim was opened with '-M'
  api.nvim_buf_set_option(bufnr, 'modifiable', true)

  api.nvim_buf_set_lines(bufnr, 0, -1, true, lines)

  api.nvim_buf_set_option(bufnr, 'modifiable', false)

  -- Set tabstop before calculating the buffer width so that the correct width
  -- is calculated
  api.nvim_buf_set_option(bufnr, 'tabstop', ts)

  local opts1 = vim.deepcopy(opts or {})
  opts1.height = opts1.height or #lines
  opts1.width  = opts1.width or bufnr_calc_width(bufnr, lines)

  local win_id = api.nvim_open_win(bufnr, false, opts1)

  if opts1.style == 'minimal' then
    -- If 'signcolumn' = auto:1-2, then a empty signcolumn will appear and cause
    -- line wrapping.
    api.nvim_win_set_option(win_id, 'signcolumn', 'no')
  end

  vim.cmd("autocmd CursorMoved,CursorMovedI,BufLeave <buffer> ++once lua pcall(vim.api.nvim_win_close, "
    ..win_id..", true)")

  return win_id, bufnr
end

return popup
