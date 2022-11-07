local M = {}

function M.check()
   local fns = vim.fn
   local report_ok = fns['health#report_ok']
   local report_error = fns['health#report_error']

   local ok, v = pcall(vim.fn.systemlist, { 'git', '--version' })

   if not ok then
      report_error(v)
   else
      report_ok(v[1])
   end
end

return M
