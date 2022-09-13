local gsd = require("gitsigns.debug")

local pwrap = require('gitsigns.async').pwrap
local subprocess = require('gitsigns.subprocess')

local run_job = pwrap(subprocess.run_job, 2)

local M = {PrInfo = {author = {}, }, }













M.associated_prs = function(toplevel, sha)
   local ok, code_or_err, _, stdout = run_job({
      command = 'gh',
      cwd = toplevel,
      args = {
         'pr', 'list',
         '--search', sha,
         '--state', 'merged',
         '--json', 'url,author,title,number',
      },
   })

   if not ok then
      gsd.dprint(code_or_err)
      return {}
   end

   if code_or_err ~= 0 then
      gsd.dprint('gh command returned ' .. vim.inspect(code_or_err))
      return {}
   end

   return vim.json.decode(stdout)
end

return M
