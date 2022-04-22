local M = {}

local callbacks: {string:function} = {}

function M._exec(id: string)
  callbacks[id]()
end

local F = M as {string:any}

function M.set(fn: function, is_expr: boolean): string
  local id: string

  if jit then
    id = 'cb'..string.format("%p", fn)
  else
    id = 'cb'..tostring(fn):match('function: (.*)')
  end

  if is_expr then
    F[id] = fn
    return string.format("v:lua.require'gitsigns.nvim.callbacks'."..id)
  else
    callbacks[id] = function() fn() end
    return string.format('lua require("gitsigns.nvim.callbacks")._exec("%s")', id)
  end
end

return M
