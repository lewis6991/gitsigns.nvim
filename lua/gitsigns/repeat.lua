local M = {}

function M.mk_repeatable(fn)
  return function(...)
    local args = { ... }
    local nargs = select('#', ...)
    vim.go.operatorfunc = "v:lua.require'gitsigns.repeat'.repeat_action"

    M.repeat_action = function()
      fn(unpack(args, 1, nargs))
      if vim.fn.exists('*repeat#set') == 1 then
        local action = vim.api.nvim_replace_termcodes(
          string.format('<cmd>call %s()<cr>', vim.go.operatorfunc),
          true,
          true,
          true
        )
        vim.fn['repeat#set'](action, -1)
      end
    end

    vim.cmd('normal! g@l')
  end
end

return M
