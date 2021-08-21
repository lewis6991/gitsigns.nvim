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
      return width + 1
   end)
end


local function expand_height(win_id, nlines)
   local newheight = 0
   for _ = 0, 50 do
      local winheight = api.nvim_win_get_height(win_id)
      if newheight > winheight then

         break
      end
      local wd = api.nvim_win_call(win_id, function()
         return vim.fn.line('w$')
      end)
      if wd >= nlines then
         break
      end
      newheight = winheight + nlines - wd
      api.nvim_win_set_height(win_id, newheight)
   end
end

function popup.create(lines, opts)
   local ts = api.nvim_buf_get_option(0, 'tabstop')
   local bufnr = api.nvim_create_buf(false, true)
   assert(bufnr, "Failed to create buffer")


   api.nvim_buf_set_option(bufnr, 'modifiable', true)

   api.nvim_buf_set_lines(bufnr, 0, -1, true, lines)

   api.nvim_buf_set_option(bufnr, 'modifiable', false)



   api.nvim_buf_set_option(bufnr, 'tabstop', ts)

   local opts1 = vim.deepcopy(opts or {})
   opts1.height = opts1.height or #lines
   opts1.width = opts1.width or bufnr_calc_width(bufnr, lines)

   local win_id = api.nvim_open_win(bufnr, false, opts1)

   if not opts.height then
      expand_height(win_id, #lines)
   end

   if opts1.style == 'minimal' then


      api.nvim_win_set_option(win_id, 'signcolumn', 'no')
   end



   vim.cmd("augroup GitsignsPopup" .. win_id)
   vim.cmd("autocmd CursorMoved,CursorMovedI * " ..
   ("lua package.loaded['gitsigns.popup'].close(%d)"):format(win_id))
   vim.cmd("augroup END")

   return win_id, bufnr
end

function popup.close(win_id)
   if api.nvim_get_current_win() ~= win_id then

      vim.cmd("silent! augroup! GitsignsPopup" .. win_id)
      pcall(api.nvim_win_close, win_id, true)
   end
end

return popup
