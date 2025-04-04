--- @meta

--- Apply a function to all values of a table.
---
---@generic K, T1, T2
---@param func fun(value: T1): T2 Function
---@param t table<K, T1> Table
---@return table<K, T2> : Table of transformed values
function vim.tbl_map(func, t) end
