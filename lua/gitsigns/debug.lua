local M = {
   debug_mode = false,
   messages = {},
}

function M.dprint(msg, bufnr, caller)
   if not M.debug_mode then
      return
   end
   local name = caller or debug.getinfo(2, 'n').name or ''
   local msg2
   if bufnr then
      msg2 = string.format('%s(%s): %s', name, bufnr, msg)
   else
      msg2 = string.format('%s: %s', name, msg)
   end
   table.insert(M.messages, msg2)
end

function M.eprint(msg)

   if vim.in_fast_event() then
      vim.schedule(function()
         print('error: ' .. msg)
      end)
   else
      print('error: ' .. msg)
   end
end

return M
