local lookups: {string:string} = {
  autocmd = "autocmds",
  augroup = "autocmds",
  highlight = "highlights",
}

local record NvimModule
  augroup: function(string, vim.api.AugroupOpts)
  autocmd: function(string|{string}, vim.api.AutoCmdOpts)
  highlight: function(string, {string:any})
end

return setmetatable(NvimModule, {
  __index = function(t: table, k: string): any
    local modname = lookups[k]
    if not modname then
      return
    end

    local require_ = require as function(string): table
    local mod = require_("gitsigns.nvim." .. modname)

    t[k] = mod[k]
    return t[k]
  end,
})
