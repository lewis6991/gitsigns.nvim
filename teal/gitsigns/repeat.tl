local api = vim.api

local record M
  mk_repeatable: function<A1,A2>(fn: function(A1, A2)): function(A1, A2)
  mk_repeatable: function<A1>   (fn: function(A1)    ): function(A1)
  repeat_action: function()
end


function M.mk_repeatable(fn: function): function
  return function(...: any)
    local args = {...}
    local nargs = select('#', ...)
    vim.go.operatorfunc = "v:lua.require'gitsigns.repeat'.repeat_action"

    M.repeat_action = function()
      fn(unpack(args, 1, nargs))
      if vim.fn.exists('*repeat#set') == 1 then
        local action = api.nvim_replace_termcodes(
          string.format('<cmd>call %s()<cr>', vim.go.operatorfunc),
          true, true, true)
        vim.fn['repeat#set'](action, -1)
      end
    end

    vim.cmd'normal! g@l'
  end
end

return M
