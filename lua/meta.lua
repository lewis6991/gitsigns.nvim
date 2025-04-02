--- @meta

--- @class vim.cmd
--- @overload fun(command: string)
--- @field [string] fun(cmd?: string|vim.api.keyset.cmd)
vim.cmd = nil

--- @class vim.Option.fillchars : vim.Option
--- @field get fun(): table<string, string>
vim.opt.fillchars = nil

--- @class vim.Option.diffopt : vim.Option
--- @field get fun(): string[]
vim.opt.diffopt = nil

--- Apply a function to all values of a table.
---
---@generic K, T, T2
---@param func fun(value: T): T2 Function
---@param t table<K, T> Table
---@return table<K, T2> : Table of transformed values
function vim.tbl_map(func, t)
  vim.validate('func', func, 'callable')
  vim.validate('t', t, 'table')

  local rettab = {} --- @type table<K,T2>
  for k, v in pairs(t) do
    rettab[k] = func(v)
  end
  return rettab
end
