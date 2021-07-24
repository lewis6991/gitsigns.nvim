
local DiffResult = {}

return function(fa, fb, algorithm)
   local a = vim.tbl_isempty(fa) and '' or table.concat(fa, '\n') .. '\n'
   local b = vim.tbl_isempty(fb) and '' or table.concat(fb, '\n') .. '\n'
   return vim.xdl_diff(a, b, {
      hunk_lines = true,
      algorithm = algorithm,
   })
end
