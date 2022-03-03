local require_ = require

local lookups = {
   autocmd = "autocmds",
   augroup = "autocmds",
   highlight = "highlights",
}

local NvimModule = {}





return setmetatable(NvimModule, {
   __index = function(t, k)
      local modname = lookups[k]
      if not modname then
         return
      end

      local mod = require_("gitsigns.nvim." .. modname)

      t[k] = mod[k]
      return t[k]
   end,
})
