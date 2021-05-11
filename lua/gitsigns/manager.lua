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
local util = require('gitsigns.util')
local git = require('gitsigns.git')
local gs_hunks = require("gitsigns.hunks")

local config = require('gitsigns.config').config

local api = vim.api

local M = {}










local function apply_win_signs0(bufnr, pending, top, bot, sec)
   if not pending then return end



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





   if first_apply and config.use_decoration_api then
      schedule_sign(next(pending))
   end

   signs.add(config, bufnr, scheduled, sec)
end

function M.apply_win_signs(bufnr, top, bot)
   local bcache = cache[bufnr]
   if not bcache then return end



   local first_apply = top == nil

   if first_apply then
      signs.remove(bufnr, nil, true)
      signs.remove(bufnr, nil, false)
   end

   apply_win_signs0(bufnr, bcache.sec.pending_signs, top, bot, true)
   apply_win_signs0(bufnr, bcache.main.pending_signs, top, bot, false)
end




local function speculate_signs(buf, last_orig, last_new)
   if last_new < last_orig then



   elseif last_new > last_orig then


      if last_orig == 0 then

         local placed = signs.get(buf, 1)[1]
         local place_empty = signs.has_empty(buf)


         if not placed or not vim.startswith(placed, 'GitSignsTopDelete') then

            for i = 1, last_new do
               signs.add_one(config, buf, i, 'add')
               if place_empty then
                  signs.add_empty_sec(config, buf, i)
               end
            end
         else
            signs.remove(buf, 1)
         end
      else
         local placed = signs.get(buf, last_orig)[last_orig]
         local place_empty = signs.has_empty(buf)


         if not placed or not vim.startswith(placed, 'GitSignsDelete') then

            for i = last_orig + 1, last_new do
               signs.add_one(config, buf, i, 'add')
               if place_empty then
                  signs.add_empty_sec(config, buf, i)
               end
            end
         end
      end
   else


      local placed = signs.get(buf, last_orig)[last_orig]


      if not placed then
         signs.add_one(config, buf, last_orig, 'change')
         if signs.has_empty(buf) then
            signs.add_empty_sec(config, buf, last_orig)
         end
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
   if not cache[bufnr] then return end

   local lnum = row + 1

   for _, hunk in ipairs(cache[bufnr].main.hunks) do
      if lnum >= hunk.start and lnum <= hunk.vend then
         local regions = require('gitsigns.word_diff').process(hunk.lines)
         for _, region in ipairs(regions) do
            if region[2] == '+' then
               local line = region[1]
               if hunk.start + (line / 2) - 1 == lnum then
                  local scol = region[3] - 1
                  local ecol = region[4] - 1
                  api.nvim_buf_set_extmark(bufnr, ns, row, scol - 1, {
                     end_col = ecol,
                     hl_group = 'GitSignsAddLn',
                     ephemeral = true,
                  })
               end
            end
         end
         break
      end
   end
end

local function staged_signs_enabled(c)
   return config.staged_signs and c.main.base == nil or c.sec.base ~= nil
end

local update_cnt = 0

local update0 = async(function(bufnr, bcache)
   bcache = bcache or cache[bufnr]
   if not bcache then
      error('Cache for buffer ' .. bufnr .. ' was nil')
      return
   end

   await(scheduler())
   local buftext = api.nvim_buf_get_lines(bufnr, 0, -1, false)
   local git_obj = bcache.git_obj

   local show_sec = staged_signs_enabled(bcache)

   for i, o in ipairs({ bcache.main, bcache.sec }) do
      local sec = i == 2

      if sec and not show_sec then
         break
      end

      local compare_object = bcache:get_compare_obj(o.base, sec)

      if config.use_internal_diff then
         local diff = require('gitsigns.diff')
         if not o.compare_text or config._refresh_staged_on_update then
            o.compare_text = await(git_obj:get_show_text(compare_object))
         end
         o.hunks = diff.run_diff(o.compare_text, buftext, config.diff_algorithm)
      else
         await(git_obj:get_show(compare_object, o.compare_file))
         o.hunks = await(git.run_diff(o.compare_file, buftext, config.diff_algorithm))
      end

      o.pending_signs = gs_hunks.process_hunks(o.hunks)
   end



   if config.staged_signs and bcache.main.base == nil and bcache.sec.base == nil then
      local fill_empty = false
      for i, ms in pairs(bcache.main.pending_signs or {}) do
         local ps = bcache.sec.pending_signs[i]
         if ps then
            if ps.type == ms.type then
               bcache.sec.pending_signs[i] = nil
            else
               fill_empty = true
            end
         end
      end



      if fill_empty then
         for i, _ in pairs(bcache.main.pending_signs or {}) do
            local ps = bcache.sec.pending_signs[i]
            if not ps then
               bcache.sec.pending_signs[i] = { type = 'empty', count = 0 }
            end
         end
      end
   end

   await(scheduler())



   M.apply_win_signs(bufnr)

   Status:update(bufnr, gs_hunks.get_summary(bcache.main.hunks, git_obj.abbrev_head))

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
