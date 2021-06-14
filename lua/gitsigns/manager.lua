local a = require('plenary.async_lib.async')
local await = a.await
local async = a.async
local void = a.void
local scheduler = a.scheduler

local sleep = require('plenary.async_lib.util').sleep

local gs_cache = require('gitsigns.cache')
local CacheEntry = gs_cache.CacheEntry
local cache = gs_cache.cache

local signs = require('gitsigns.signs')
local Sign = signs.Sign

local Status = require("gitsigns.status")

local debounce_trailing = require('gitsigns.debounce').debounce_trailing
local gs_debug = require("gitsigns.debug")
local dprint = gs_debug.dprint
local eprint = gs_debug.eprint
local util = require('gitsigns.util')
local git = require('gitsigns.git')
local gs_hunks = require("gitsigns.hunks")

local config = require('gitsigns.config').config

local api = vim.api

local M = {}










function M.apply_win_signs(bufnr, pending, top, bot)


   local first_apply = top == nil

   if config.use_decoration_api then

      top = top or vim.fn.line('w0')
      bot = bot or vim.fn.line('w$')
   else
      top = top or 1
      bot = bot or vim.fn.line('$')
   end

   local scheduled = {}

   local function schedule_sign(n, _)
      if n and pending[n] then
         scheduled[n] = pending[n]
         pending[n] = nil
      end
   end

   for lnum = top, bot do
      schedule_sign(lnum)
   end

   if first_apply then
      signs.remove(bufnr)





      if config.use_decoration_api then
         schedule_sign(next(pending))
      end
   end

   signs.add(config, bufnr, scheduled)

end




local function speculate_signs(buf, last_orig, last_new)
   if last_new < last_orig then



   elseif last_new > last_orig then


      if last_orig == 0 then

         local placed = signs.get(buf, 1)[1]


         if not placed or not vim.startswith(placed, 'GitSignsTopDelete') then

            for i = 1, last_new do
               signs.add(config, buf, { [i] = { type = 'add', count = 0 } })
            end
         else
            signs.remove(buf, 1)
         end
      else
         local placed = signs.get(buf, last_orig)[last_orig]


         if not placed or not vim.startswith(placed, 'GitSignsDelete') then

            for i = last_orig + 1, last_new do
               signs.add(config, buf, { [i] = { type = 'add', count = 0 } })
            end
         end
      end
   else


      local placed = signs.get(buf, last_orig)[last_orig]


      if not placed then
         signs.add(config, buf, { [last_orig] = { type = 'change', count = 0 } })
      end
   end
end

M.on_lines = function(buf, last_orig, last_new)
   if not cache[buf] then
      dprint('Cache for buffer ' .. buf .. ' was nil. Detaching')
      return true
   end

   speculate_signs(buf, last_orig, last_new)
   M.update_debounced(buf)
end

local ns = api.nvim_create_namespace('gitsigns')

M.apply_word_diff = function(bufnr, row)
   if not cache[bufnr] or not cache[bufnr].hunks then return end

   local lnum = row + 1
   local cols = #api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1]

   for _, hunk in ipairs(cache[bufnr].hunks) do
      if lnum >= hunk.start and lnum <= hunk.vend then
         local size = #hunk.lines / 2
         local regions = require('gitsigns.diff').run_word_diff(hunk.lines)
         for _, region in ipairs(regions) do
            local line = region[1]
            if lnum == hunk.start + line - size - 1 and
               vim.startswith(hunk.lines[line], '+') then
               local rtype = region[2]
               local scol = region[3] - 1
               local ecol = region[4] - 1
               if scol <= cols then
                  if ecol > cols then ecol = cols end
                  api.nvim_buf_set_extmark(bufnr, ns, row, scol, {
                     end_col = ecol,
                     hl_group = rtype == 'add' and 'GitSignsAddLn' or
                     rtype == 'change' and 'GitSignsChangeLn' or
                     'GitSignsDeleteLn',
                     ephemeral = true,
                  })
               end
            end
         end
         break
      end
   end
end

local update_cnt = 0

local update0 = async(function(bufnr, bcache)
   bcache = bcache or cache[bufnr]
   if not bcache then
      eprint('Cache for buffer ' .. bufnr .. ' was nil')
      return
   end
   bcache.hunks = nil

   await(scheduler())
   local buftext = api.nvim_buf_get_lines(bufnr, 0, -1, false)
   local git_obj = bcache.git_obj

   local compare_object = bcache.get_compare_obj(bcache)

   if config.use_internal_diff then
      local diff = require('gitsigns.diff')
      if not bcache.compare_text or config._refresh_staged_on_update then
         bcache.compare_text = await(git_obj:get_show_text(compare_object))
      end
      bcache.hunks = diff.run_diff(bcache.compare_text, buftext, config.diff_algorithm)
   else
      await(git_obj:get_show(compare_object, bcache.compare_file))
      bcache.hunks = await(git.run_diff(bcache.compare_file, buftext, config.diff_algorithm))
   end
   bcache.pending_signs = gs_hunks.process_hunks(bcache.hunks)

   await(scheduler())



   M.apply_win_signs(bufnr, bcache.pending_signs)

   Status:update(bufnr, gs_hunks.get_summary(bcache.hunks, git_obj.abbrev_head))

   update_cnt = update_cnt + 1

   local update_str = string.format('updates: %s, jobs: %s', update_cnt, util.job_cnt)
   dprint(update_str, bufnr, 'update')
   if config.debug_mode then
      api.nvim_set_var('gs_dev', update_str)
   end
end)





do
   local running = false
   local scheduled = {}
   M.update = async(function(bufnr)
      scheduled[bufnr] = true
      if not running then
         running = true
         while scheduled[bufnr] do
            scheduled[bufnr] = false
            await(update0(bufnr))
         end
         running = false
      else

         while running do
            await(sleep(100))
         end
      end
   end)
end

M.setup = function()
   M.update_debounced = debounce_trailing(config.update_debounce, void(M.update))
end

return M
