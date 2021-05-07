
local M = {}

local repeat_fn: function()

function M.repeat_action()
  repeat_fn()
end

function M.mk_repeatable(fn: function): function
  return function(...)
    local args = {...}
    repeat_fn = function()
      fn(unpack(args))
      vim.cmd('silent! call repeat#set("\\<Plug>GitsignsRepeat",-1)')
    end

    repeat_fn()
  end
end

vim.api.nvim_set_keymap(
  'n',
  '<Plug>GitsignsRepeat',
  '<cmd>lua require"gitsigns.repeat".repeat_action()<CR>',
  {noremap = false, silent = true}
)

return M
