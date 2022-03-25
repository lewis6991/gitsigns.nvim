local nvim = require('gitsigns.nvim')

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

   api.nvim_win_set_var(win_id, 'gitsigns_preview', true)

   if not opts.height then
      expand_height(win_id, #lines)
   end

   if opts1.style == 'minimal' then


      api.nvim_win_set_option(win_id, 'signcolumn', 'no')
   end



   local group = 'gitsigns_popup' .. win_id
   nvim.augroup(group)
   local old_cursor = api.nvim_win_get_cursor(0)

   nvim.autocmd({ 'CursorMoved', 'CursorMovedI' }, {
      group = group,
      callback = function()
         local cursor = api.nvim_win_get_cursor(0)

         if (old_cursor[1] ~= cursor[1] or old_cursor[2] ~= cursor[2]) and
            api.nvim_get_current_win() ~= win_id then

            nvim.augroup(group)
            pcall(api.nvim_win_close, win_id, true)
            return
         end
         old_cursor = cursor
      end,
   })

   return win_id, bufnr
end


function popup.is_open()
   for _, winid in ipairs(api.nvim_list_wins()) do
      local exists = pcall(api.nvim_win_get_var, winid, 'gitsigns_preview')
      if exists then
         return true
      end
   end
   return false
end

return popup
