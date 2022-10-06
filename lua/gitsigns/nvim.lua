local api = vim.api

local lookups = {
   autocmd = "autocmds",
   augroup = "autocmds",
   doautocmd = "autocmds",
   highlight = "highlights",
   command = "command",
}

local NvimModule = {}







return setmetatable(NvimModule, {
   __index = function(t, k)
      local modname = lookups[k]
      if not modname then
         return
      end

      local require_ = require
      local mod = require_("gitsigns.nvim." .. modname)

      t[k] = mod[k]
      return t[k]
   end,
})
