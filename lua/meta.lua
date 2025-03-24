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

--- @class vim.fn
--- @field [string] fun(...:any): any
vim.fn = nil
