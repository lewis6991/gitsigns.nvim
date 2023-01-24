local uv = vim.loop

local M = {}



local handles = {}

M.handles = handles

function M.print_handles()
   local none = true
   for _, e in pairs(handles) do
      local handle, longlived, tr = unpack(e)
      if handle and not longlived and not handle:is_closing() then
         print('')
         print(tr)
         none = false
      end
   end
   if none then
      print('No active handles')
   end
end

vim.api.nvim_create_autocmd('VimLeavePre', {
   callback = function()
      for _, e in pairs(handles) do
         local handle = e[1]
         if handle and not handle:is_closing() then
            handle:close()
         end
      end
   end,
})

function M.new_timer(longlived)
   local r = uv.new_timer()
   table.insert(handles, { r, longlived, debug.traceback() })
   return r
end

function M.new_fs_poll(longlived)
   local r = uv.new_fs_poll()
   table.insert(handles, { r, longlived, debug.traceback() })
   return r
end

function M.new_pipe(ipc)
   local r = uv.new_pipe(ipc)
   table.insert(handles, { r, false, debug.traceback() })
   return r
end

function M.spawn(cmd, opts, on_exit)
   local handle, pid = uv.spawn(cmd, opts, on_exit)
   if handle then
      table.insert(handles, { handle, false, cmd .. ' ' .. vim.inspect(opts) })
   end
   return handle, pid
end

return M
