
local DiffResult = {}

return function(fa, fb, _diff_algo)
   local a = vim.tbl_isempty(fa) and '' or table.concat(fa, '\n') .. '\n'
   local b = vim.tbl_isempty(fb) and '' or table.concat(fb, '\n') .. '\n'
   local results = {}
   vim.xdl_diff(a, b, {
      hunk_func = function(
         sa, ca, sb, cb)



         if ca > 0 then sa = sa + 1 end
         if cb > 0 then sb = sb + 1 end

         results[#results + 1] = { sa, ca, sb, cb }
         return 0
      end,
   })
   return results
end
