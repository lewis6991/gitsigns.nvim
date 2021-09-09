local git = require('gitsigns.git')

local gs_hunks = require("gitsigns.hunks")
local Hunk = gs_hunks.Hunk
local util = require('gitsigns.util')
local scheduler = require('plenary.async.util').scheduler

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

   if not util.is_unix then

      scheduler()
   end

   local file_buf = util.tmpname() .. '_buf'
   local file_cmp = util.tmpname() .. '_cmp'

   write_to_file(file_buf, text_buf)
   write_to_file(file_cmp, text_cmp)

















   git.command({
      '-c', 'core.safecrlf=false',
      'diff',
      '--color=never',
      '--' .. (indent_heuristic and '' or 'no-') .. 'indent-heuristic',
      '--diff-algorithm=' .. diff_algo,
      '--patch-with-raw',
      '--unified=0',
      file_cmp,
      file_buf,
   }, {
      on_stdout = function(_, line)
         if vim.startswith(line, '@@') then
            table.insert(results, gs_hunks.parse_diff_line(line))
         elseif #results > 0 then
            table.insert(results[#results].lines, line)
         end
      end,
   })
   os.remove(file_buf)
   os.remove(file_cmp)
   return results
end

return M
