local root = vim.fn.getcwd()

vim.opt.runtimepath:prepend(root)
vim.opt.packpath = vim.opt.runtimepath:get()

package.path = table.concat({
  root .. '/lua/?.lua',
  root .. '/lua/?/init.lua',
  root .. '/test/?.lua',
  root .. '/test/?/init.lua',
  package.path,
}, ';')

vim.o.shadafile = 'NONE'
vim.o.swapfile = false
