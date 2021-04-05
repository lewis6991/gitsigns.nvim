local popup = {}

local api = vim.api

local function calc_width(lines: {string}): integer
  local width = 0
  for _, l in ipairs(lines) do
    local len = vim.fn.strdisplaywidth(l)
    if len > width then
      width = len
    end
  end
  return width
end

-- Wrapper of open_win that can work with older nvim versions
local function open_win(bufnr: integer, enter: boolean, opts: {string:any}): integer
  local stat, win_id = pcall(api.nvim_open_win, bufnr, enter, opts)

  if not stat then
    -- Try again with newer options removed
    opts.border = nil
    win_id = api.nvim_open_win(bufnr, enter, opts)
  end

  return win_id
end

local function bufnr_calc_width(buf: integer, lines: {string}): integer
  return api.nvim_buf_call(buf, function(): integer
    return calc_width(lines)
  end)
end

function popup.create(what: {string}, opts: {string:any}): number, number
  local bufnr = api.nvim_create_buf(false, true)
  assert(bufnr, "Failed to create buffer")

  api.nvim_buf_set_lines(bufnr, 0, -1, true, what)

  opts = opts or {}

  -- Set tabstop before calculating the buffer width so that the correct width
  -- is calculated
  if opts.tabstop then
    api.nvim_buf_set_option(bufnr, 'tabstop', opts.tabstop)
  end

  local win_id = open_win(bufnr, false, {
    border   = 'single',
    style    = 'minimal',
    relative = opts.relative or 'cursor',
    row      = opts.row or 0,
    col      = opts.col or 1,
    height   = opts.height or #what,
    width    = opts.width or bufnr_calc_width(bufnr, what)
  })

  vim.lsp.util.close_preview_autocmd({'CursorMoved', 'CursorMovedI'}, win_id)

  api.nvim_win_set_option(win_id, 'winhl', string.format('NormalFloat:Normal' ))

  return win_id, bufnr
end

return popup
