local api = vim.api

local lookups: {string:string} = {
  autocmd = "autocmds",
  augroup = "autocmds",
  highlight = "highlights",
  command = "command",
}

local record NvimModule
  augroup: function(string, api.AugroupOpts)
  autocmd: function(string|{string}, api.AutoCmdOpts)
  highlight: function(string, {string:any})
  command: function(name: string, fn: function(api.UserCmdParams), opts: api.UserCmdOpts)
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
