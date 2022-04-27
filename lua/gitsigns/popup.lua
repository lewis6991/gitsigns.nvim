local nvim = require('gitsigns.nvim')

local popup = {HlMark = {}, }










local HlMark = popup.HlMark

local api = vim.api

local function bufnr_calc_width(bufnr, lines)
   return api.nvim_buf_call(bufnr, function()
      local width = 0
      for _, l in ipairs(lines) do
         if vim.fn.type(l) == vim.v.t_string then
            local len = vim.fn.strdisplaywidth(l)
            if len > width then
               width = len
            end
         end
      end
      return width + 1
   end)
end


local function expand_height(winid, nlines)
   local newheight = 0
   for _ = 0, 50 do
      local winheight = api.nvim_win_get_height(winid)
      if newheight > winheight then

         break
      end
      local wd = api.nvim_win_call(winid, function()
         return vim.fn.line('w$')
      end)
      if wd >= nlines then
         break
      end
      newheight = winheight + nlines - wd
      api.nvim_win_set_height(winid, newheight)
   end
end

local function offset_hlmarks(hlmarks, row_offset)
   for _, h in ipairs(hlmarks) do
      if h.start_row then
         h.start_row = h.start_row + row_offset
      end
      if h.end_row then
         h.end_row = h.end_row + row_offset
      end
   end
end

local function process_linesspec(fmt)
   local lines = {}
   local hls = {}

   local row = 0
   for _, section in ipairs(fmt) do
      local sec = {}
      local pos = 0
      for _, part in ipairs(section) do
         local text = part[1]
         local hl = part[2]

         sec[#sec + 1] = text

         local srow = row
         local scol = pos

         local ts = vim.split(text, '\n')

         if #ts > 1 then
            pos = 0
            row = row + #ts - 1
         else
            pos = pos + #text
         end

         if type(hl) == "string" then
            hls[#hls + 1] = {
               hl_group = hl,
               start_row = srow,
               end_row = row,
               start_col = scol,
               end_col = pos,
            }
         else
            offset_hlmarks(hl, srow)
            vim.list_extend(hls, hl)
         end
      end
      for _, l in ipairs(vim.split(table.concat(sec, ''), '\n')) do
         lines[#lines + 1] = l
      end
      row = row + 1
   end

   return lines, hls
end

function popup.create0(lines, opts)
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

   local winid = api.nvim_open_win(bufnr, false, opts1)

   api.nvim_win_set_var(winid, 'gitsigns_preview', true)

   if not opts.height then
      expand_height(winid, #lines)
   end

   if opts1.style == 'minimal' then


      api.nvim_win_set_option(winid, 'signcolumn', 'no')
   end



   local group = 'gitsigns_popup' .. winid
   nvim.augroup(group)
   local old_cursor = api.nvim_win_get_cursor(0)

   nvim.autocmd({ 'CursorMoved', 'CursorMovedI' }, {
      group = group,
      callback = function()
         local cursor = api.nvim_win_get_cursor(0)

         if (old_cursor[1] ~= cursor[1] or old_cursor[2] ~= cursor[2]) and
            api.nvim_get_current_win() ~= winid then

            nvim.augroup(group)
            pcall(api.nvim_win_close, winid, true)
            return
         end
         old_cursor = cursor
      end,
   })

   return winid, bufnr
end

local ns = api.nvim_create_namespace('gitsigns_popup')

function popup.create(lines_spec, opts)
   local lines, highlights = process_linesspec(lines_spec)
   local winnr, bufnr = popup.create0(lines, opts)

   for _, hl in ipairs(highlights) do
      local ok, err = pcall(api.nvim_buf_set_extmark, bufnr, ns, hl.start_row, hl.start_col or 0, {
         hl_group = hl.hl_group,
         end_row = hl.end_row,
         end_col = hl.end_col,
         hl_eol = true,
      })
      if not ok then
         error(vim.inspect(hl) .. '\n' .. err)
      end
   end

   return winnr, bufnr
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
