local log = require('gitsigns.debug.log')

local M = {}

local function process(raw_item, path)
   if path[#path] == vim.inspect.METATABLE then
      return nil
   elseif type(raw_item) == "function" then
      return nil
   elseif type(raw_item) == "table" then
      local key = path[#path]
      if key == 'compare_text' or key == 'compare_text_head' then
         local item = raw_item
         return { '...', length = #item, head = item[1] }
      elseif not vim.tbl_isempty(raw_item) and key == 'staged_diffs' then
         return { '...', length = #vim.tbl_keys(raw_item) }
      end
   end
   return raw_item
end

function M.dump_cache()
   -- TODO(lewis6991): hack: use package.loaded to avoid circular deps
   local cache = (package.loaded['gitsigns.cache']).cache
   local text = vim.inspect(cache, { process = process })
   vim.api.nvim_echo({ { text } }, false, {})
   return cache
end

function M.debug_messages(noecho)
   if noecho then
      return log.messages
   else
      for _, m in ipairs(log.messages) do
         vim.api.nvim_echo({ { m } }, false, {})
      end
   end
end

function M.clear_debug()
   log.messages = {}
end

return M
