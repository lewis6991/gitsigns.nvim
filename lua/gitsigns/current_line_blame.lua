local a = require('plenary.async_lib.async')
local await = a.await
local async_void = a.async_void
local scheduler = a.scheduler

local cache = require('gitsigns.cache').cache
local config = require('gitsigns.config').config

local api = vim.api

local current_buf = api.nvim_get_current_buf

local namespace = api.nvim_create_namespace('gitsigns_blame')

local M = {}





M.reset = function(bufnr)
   bufnr = bufnr or current_buf()
   api.nvim_buf_del_extmark(bufnr, namespace, 1)
end

M.run = async_void(function()
   local bufnr = current_buf()
   local bcache = cache[bufnr]
   if not bcache or not bcache.git_obj.object_name then
      return
   end

   local buftext = api.nvim_buf_get_lines(bufnr, 0, -1, false)
   local lnum = api.nvim_win_get_cursor(0)[1]
   local result = await(bcache.git_obj:run_blame(buftext, lnum))

   await(scheduler())

   M.reset(bufnr)
   api.nvim_buf_set_extmark(bufnr, namespace, lnum - 1, 0, {
      id = 1,
      virt_text = config.current_line_blame_formatter(bcache.git_obj.username, result),
      virt_text_pos = config.current_line_blame_position,
   })
end)

M.setup = function()
   vim.cmd('augroup gitsigns_blame | autocmd! | augroup END')
   for k, _ in pairs(cache) do
      M.reset(k)
   end
   if config.current_line_blame then
      for func, events in pairs({
            run = 'CursorHold',
            reset = 'CursorMoved',
         }) do
         vim.cmd('autocmd gitsigns_blame ' .. events .. ' * lua require("gitsigns.current_line_blame").' .. func .. '()')
      end
   end
end

return M
