local popup = {}

local api = vim.api

local function visible_len(x, softtabstop)

   local x2 = x:gsub('\t', string.rep(' ', softtabstop))
   return #x2
end

local function calc_width(lines, bufnr)
   local width = 0
   local sts = api.nvim_buf_get_option(bufnr, 'softtabstop')
   for _, l in ipairs(lines) do
      local len = visible_len(l, sts)
      if len > width then
         width = len
      end
   end
   return width
end

function popup.create(what, opts)
   local bufnr = api.nvim_create_buf(false, true)
   assert(bufnr, "Failed to create buffer")

   api.nvim_buf_set_lines(bufnr, 0, -1, true, what)

   opts = opts or {}

   local win_id = api.nvim_open_win(bufnr, false, {
      relative = opts.relative,
      row = opts.row or 0,
      col = opts.col or 0,
      height = opts.height or #what,
      width = opts.width or calc_width(what, bufnr),
   })

   vim.lsp.util.close_preview_autocmd({ 'CursorMoved', 'CursorMovedI' }, win_id)

   if opts.highlight then
      api.nvim_win_set_option(win_id, 'winhl', string.format('Normal:%s', opts.highlight))
   end

   return win_id, bufnr
end

return popup
