local cmd = vim.cmd

local M = {}

local callbacks: {string:function} = {}

function M._exec(id: string)
  callbacks[id]()
end

local function set_callback(fn: function): string
  local id = string.format("%p", fn)
  callbacks[id] = function() fn() end
  return string.format('lua require("gitsigns.nvim.autocmds_compat")._exec("%s")', id)
end

local function flatten(x: string|{string}): string
  if x is {string} then
    return table.concat(x, ",")
  else
    return x
  end
end

function M.autocmd(event: string|{string}, opts: vim.api.AutoCmdOpts)
  cmd(table.concat({
    'autocmd',
    opts.group or '',
    flatten(event),
    opts.pattern and flatten(opts.pattern) or '*',
    opts.once and '++once' or '',
    opts.nested and '++nested' or '',
    type(opts.callback) == 'function' and set_callback(opts.callback) or opts.command,
  }, " "))
end

function M.augroup(name: string, opts: vim.api.AugroupOpts)
  opts = opts or {}

  cmd("augroup " .. name)
  if opts.clear ~= false then
    cmd "autocmd!"
  end
  cmd "augroup END"
end

return M
