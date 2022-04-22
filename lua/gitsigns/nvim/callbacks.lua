local M = {}

local callbacks = {}

function M._exec(id, ...)
   callbacks[id](...)
end

local F = M

function M.set(fn, is_expr, args)
   local id

   if jit then
      id = 'cb' .. string.format("%p", fn)
   else
      id = 'cb' .. tostring(fn):match('function: (.*)')
   end

   if is_expr then
      F[id] = fn
      return string.format("v:lua.require'gitsigns.nvim.callbacks'." .. id)
   else
      if args then
         callbacks[id] = fn
         return string.format('lua require("gitsigns.nvim.callbacks")._exec("%s", %s)', id, args)
      else
         callbacks[id] = function() fn() end
         return string.format('lua require("gitsigns.nvim.callbacks")._exec("%s")', id)
      end
   end
end

return M
