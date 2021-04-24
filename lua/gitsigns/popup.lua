local popup = {}

local api = vim.api

local function calc_width(lines)
   local width = 0
   for _, l in ipairs(lines) do
      local len = vim.fn.strdisplaywidth(l)
      if len > width then
         width = len
      end
   end
   return width
end


local function open_win(bufnr, enter, opts)
   local stat, win_id = pcall(api.nvim_open_win, bufnr, enter, opts)

   if not stat then

      opts.border = nil
      win_id = api.nvim_open_win(bufnr, enter, opts)
   elseif opts.border then
      api.nvim_win_set_option(win_id, 'winhl', string.format('NormalFloat:Normal'))
   end

   return win_id
end

local function bufnr_calc_width(buf, lines)
   return api.nvim_buf_call(buf, function()
      return calc_width(lines)
   end)
end

function popup.create(what, opts)
   local ts = api.nvim_buf_get_option(0, 'tabstop')
   local bufnr = api.nvim_create_buf(false, true)
   assert(bufnr, "Failed to create buffer")

   api.nvim_buf_set_lines(bufnr, 0, -1, true, what)

   opts = opts or {}



   if opts.tabstop then
      api.nvim_buf_set_option(bufnr, 'tabstop', ts)
   end

   local win_id = open_win(bufnr, false, {
      border = opts.border or 'single',
      style = opts.style or 'minimal',
      relative = opts.relative or 'cursor',
      row = opts.row or 0,
      col = opts.col or 1,
      height = opts.height or #what,
      width = opts.width or bufnr_calc_width(bufnr, what),
   })

   vim.lsp.util.close_preview_autocmd({ 'CursorMoved', 'CursorMovedI' }, win_id)

   return win_id, bufnr
end

return popup
