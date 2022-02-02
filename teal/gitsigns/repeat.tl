local tbl = require('plenary.tbl')
local api = vim.api
local M = {}

local repeat_fn: function()

function M.repeat_action()
  repeat_fn()
end

function M.mk_repeatable(fn: function): function
  return function(...: any)
    local args = tbl.pack(...)
    repeat_fn = function()
      fn(tbl.unpack(args))
      local vimfn = vim.fn as {string:function}
      local sequence = string.format('%sGitsignsRepeat',
        api.nvim_replace_termcodes('<Plug>', true, true, true))
      vimfn['repeat#set'](sequence, -1)
    end

    repeat_fn()
  end
end

api.nvim_set_keymap(
  'n',
  '<Plug>GitsignsRepeat',
  '<cmd>lua require"gitsigns.repeat".repeat_action()<CR>',
  {noremap = false, silent = true}
)

return M
