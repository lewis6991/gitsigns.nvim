local api = vim.api

local void = require('gitsigns.async').void
local scheduler = require('gitsigns.async').scheduler
local awrap = require('gitsigns.async').wrap

local gs_cache = require('gitsigns.cache')
local cache = gs_cache.cache
local CacheEntry = gs_cache.CacheEntry

local nvim = require('gitsigns.nvim')
local util = require('gitsigns.util')
local manager = require('gitsigns.manager')
local message = require('gitsigns.message')

local throttle_by_id = require('gitsigns.debounce').throttle_by_id

local input = awrap(vim.ui.input, 2)

local M = {}





local bufread = void(function(bufnr, dbufnr, base, bcache)
   local comp_rev = bcache:get_compare_rev(util.calc_base(base))
   local text
   if util.calc_base(base) == util.calc_base(bcache.base) then
      text = bcache.compare_text
   else
      local err
      text, err = bcache.git_obj:get_show_text(comp_rev)
      if err then
         error(err, 2)
      end
      scheduler()
      if vim.bo[bufnr].fileformat == 'dos' then
         text = util.strip_cr(text)
      end
   end

   local modifiable = vim.bo[dbufnr].modifiable
   vim.bo[dbufnr].modifiable = true
   util.set_lines(dbufnr, 0, -1, text)

   vim.bo[dbufnr].modifiable = modifiable
   vim.bo[dbufnr].modified = false
   vim.bo[dbufnr].filetype = vim.bo[bufnr].filetype
   vim.bo[dbufnr].bufhidden = 'wipe'
end)

local bufwrite = void(function(bufnr, dbufnr, base, bcache)
   local buftext = util.buf_lines(dbufnr)
   bcache.git_obj:stage_lines(buftext)
   scheduler()
   vim.bo[dbufnr].modified = false


   if util.calc_base(base) == util.calc_base(bcache.base) then
      bcache.compare_text = buftext
      manager.update(bufnr, bcache)
   end
end)

local function run(base, diffthis, vertical)
   local bufnr = vim.api.nvim_get_current_buf()
   local bcache = cache[bufnr]
   if not bcache then
      return
   end

   local comp_rev = bcache:get_compare_rev(util.calc_base(base))
   local bufname = bcache:get_rev_bufname(comp_rev)

   if diffthis then

      vim.cmd('diffthis')

      vim.cmd(table.concat({
         'keepalt', 'aboveleft',
         vertical and 'vertical' or '',
         'split', bufname,
      }, ' '))
   else


      vim.cmd(table.concat({
         'edit', bufname,
      }, ' '))
   end

   local dbuf = vim.api.nvim_get_current_buf()

   local ok, err = pcall(bufread, bufnr, dbuf, base, bcache)

   if diffthis then
      vim.cmd('diffthis')
   end

   if not ok then
      message.error(err)
      scheduler()
      vim.cmd('bdelete')
      if diffthis then
         vim.cmd('diffoff')
      end
      return
   end

   if comp_rev == ':0' then
      vim.bo[dbuf].buftype = 'acwrite'

      nvim.autocmd('BufReadCmd', {
         group = 'gitsigns',
         buffer = dbuf,
         callback = function()
            bufread(bufnr, dbuf, base, bcache)
            if diffthis then
               vim.cmd('diffthis')
            end
         end,
      })

      nvim.autocmd('BufWriteCmd', {
         group = 'gitsigns',
         buffer = dbuf,
         callback = function()
            bufwrite(bufnr, dbuf, base, bcache)
         end,
      })
   else
      vim.bo[dbuf].buftype = 'nowrite'
      vim.bo[dbuf].modifiable = false
   end
end

M.diffthis = void(function(base, vertical)
   if vim.wo.diff then
      return
   end
   run(base, true, vertical)
end)

M.show = void(function(base)
   run(base, false)
end)

local function should_reload(bufnr)
   if not vim.bo[bufnr].modified then
      return true
   end
   local response
   while not vim.tbl_contains({ 'O', 'L' }, response) do
      response = input({
         prompt = 'Warning: The git index has changed and the buffer was changed as well. [O]K, (L)oad File:',
      })
   end
   return response == 'L'
end


M.update = throttle_by_id(void(function(bufnr)
   if not vim.wo.diff then
      return
   end

   local bcache = cache[bufnr]



   local bufname = bcache:get_rev_bufname()

   for _, w in ipairs(api.nvim_list_wins()) do
      if api.nvim_win_is_valid(w) then
         local b = api.nvim_win_get_buf(w)
         local bname = api.nvim_buf_get_name(b)
         if bname == bufname or vim.startswith(bname, 'fugitive://') then
            if should_reload(b) then
               api.nvim_buf_call(b, function()
                  vim.cmd('doautocmd BufReadCmd')
                  vim.cmd('diffthis')
               end)
            end
         end
      end
   end
end))

return M
