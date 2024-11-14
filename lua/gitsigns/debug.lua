local log = require('gitsigns.debug.log')

--- @class gitsigns.debug
local M = {}

--- @param raw_item any
--- @param path string[]
--- @return any
local function process(raw_item, path)
  --- @diagnostic disable-next-line:undefined-field
  if path[#path] == vim.inspect.METATABLE then
    return
  elseif type(raw_item) == 'function' then
    return
  elseif type(raw_item) ~= 'table' then
    return raw_item
  end
  --- @cast raw_item table<any,any>

  local key = path[#path]
  if
    vim.tbl_contains({
      'compare_text',
      'compare_text_head',
      'hunks',
      'hunks_staged',
      'staged_diffs',
    }, key)
  then
    return { '...', length = #vim.tbl_keys(raw_item), head = raw_item[next(raw_item)] }
  elseif key == 'blame' then
    return { '...', length = #vim.tbl_keys(raw_item) }
  end

  return raw_item
end

--- @return any
function M.dump_cache()
  -- TODO(lewis6991): hack: use package.loaded to avoid circular deps
  local cache = (require('gitsigns.cache')).cache
  --- @type string
  local text = vim.inspect(cache, { process = process })
  vim.api.nvim_echo({ { text } }, false, {})
end

M.debug_messages = log.show
M.clear_debug = log.clear

return M
