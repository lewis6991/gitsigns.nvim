local popup = {}

local api = vim.api

local function bufnr_calc_width(buf, lines)
   return api.nvim_buf_call(buf, function()
      local width = 0
      for _, l in ipairs(lines) do
         local len = vim.fn.strdisplaywidth(l)
         if len > width then
            width = len
         end
      end
      return width
   end)
end

function popup.create(lines, opts)
   local ts = api.nvim_buf_get_option(0, 'tabstop')
   local bufnr = api.nvim_create_buf(false, true)
   assert(bufnr, "Failed to create buffer")

   api.nvim_buf_set_lines(bufnr, 0, -1, true, lines)



   api.nvim_buf_set_option(bufnr, 'tabstop', ts)

   local opts1 = vim.deepcopy(opts or {})
   opts1.height = opts1.height or #lines
   opts1.width = opts1.width or bufnr_calc_width(bufnr, lines)

   local win_id = api.nvim_open_win(bufnr, false, opts1)

   vim.lsp.util.close_preview_autocmd({ 'CursorMoved', 'CursorMovedI' }, win_id)

   return win_id, bufnr
end

return popup
