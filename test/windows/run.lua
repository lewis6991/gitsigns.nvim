require('windows.gitsigns').setup()

require('windows.smoke')

local failures = require('windows.harness').run()

if failures > 0 then
  vim.cmd.cquit(failures)
else
  vim.cmd.qa()
end
