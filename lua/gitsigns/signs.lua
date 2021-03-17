
local M = {}

local sign_define_cache = {}

local function sign_get(name)
   if not sign_define_cache[name] then
      local s = vim.fn.sign_getdefined(name)
      if not vim.tbl_isempty(s) then
         sign_define_cache[name] = s
      end
   end
   return sign_define_cache[name]
end

function M.sign_define(name, opts, redefine)
   if redefine then
      sign_define_cache[name] = nil
      vim.fn.sign_undefine(name)
      vim.fn.sign_define(name, opts)
   elseif not sign_get(name) then
      vim.fn.sign_define(name, opts)
   end
end

return M
