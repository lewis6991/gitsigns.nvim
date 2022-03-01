local git_diff = require('gitsigns.git').diff

local gs_hunks = require("gitsigns.hunks")
local Hunk = gs_hunks.Hunk
local util = require('gitsigns.util')
local scheduler = require('gitsigns.async').scheduler

local M = {}




local function write_to_file(path, text)
   local f, err = io.open(path, 'wb')
   if f == nil then
      error(err)
   end
   for _, l in ipairs(text) do
      f:write(l)
      f:write('\n')
   end
   f:close()
end

M.run_diff = function(
   text_cmp,
   text_buf,
   diff_algo,
   indent_heuristic)

   local results = {}


   if vim.in_fast_event() then
      scheduler()
   end

   local file_buf = util.tmpname() .. '_buf'
   local file_cmp = util.tmpname() .. '_cmp'

   write_to_file(file_buf, text_buf)
   write_to_file(file_cmp, text_cmp)

















   local out = git_diff(file_cmp, file_buf, indent_heuristic, diff_algo)

   for _, line in ipairs(out) do
      if vim.startswith(line, '@@') then
         results[#results + 1] = gs_hunks.parse_diff_line(line)
      elseif #results > 0 then
         local r = results[#results]
         if line:sub(1, 1) == '-' then
            r.removed.lines[#r.removed.lines + 1] = line:sub(2)
         elseif line:sub(1, 1) == '+' then
            r.added.lines[#r.added.lines + 1] = line:sub(2)
         end
      end
   end

   os.remove(file_buf)
   os.remove(file_cmp)
   return results
end

return M
