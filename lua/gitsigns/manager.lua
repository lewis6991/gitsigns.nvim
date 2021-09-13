local void = require('gitsigns.async').void
local awrap = require('gitsigns.async').wrap

local gs_cache = require('gitsigns.cache')
local CacheEntry = gs_cache.CacheEntry
local cache = gs_cache.cache

local signs = require('gitsigns.signs')

local Status = require("gitsigns.status")

local debounce_trailing = require('gitsigns.debounce').debounce_trailing
local throttle_by_id = require('gitsigns.debounce').throttle_by_id
local gs_debug = require("gitsigns.debug")
local dprint = gs_debug.dprint
local dprintf = gs_debug.dprintf
local eprint = gs_debug.eprint
local subprocess = require('gitsigns.subprocess')
local util = require('gitsigns.util')
local run_diff = require('gitsigns.diff')

local gs_hunks = require("gitsigns.hunks")
local Hunk = gs_hunks.Hunk

local config = require('gitsigns.config').config

local api = vim.api

local M = {}











local schedule_if_buf_valid = function(buf, cb)
   vim.schedule(function()
      if vim.api.nvim_buf_is_valid(buf) then
         cb()
      end
   end)
end

local scheduler_if_buf_valid = awrap(schedule_if_buf_valid, 2)

function M.apply_win_signs(bufnr, hunks, top, bot, clear)
   if clear then
      signs.remove(bufnr)
   end






   for i, hunk in ipairs(hunks or {}) do
      if clear and i == 1 or
         top <= hunk.vend and bot >= hunk.start then
         signs.schedule(config, bufnr, gs_hunks.calc_signs(hunk))
      end
      if hunk.start > bot then
         break
      end
   end

   signs.draw(bufnr, top, bot)
end






local function speculate_signs(buf, last_orig, last_new)
   if last_new < last_orig then



   elseif last_new > last_orig then


      if last_orig == 0 then
         local placed = signs.get(buf, 1)


         if not placed or not vim.startswith(placed, 'GitSignsTopDelete') then

            for i = 1, last_new do
               signs.add(config, buf, { { type = 'add', count = 0, lnum = i } })
            end
         else
            signs.remove(buf, 1)
         end
         return true
      else
         local placed = signs.get(buf, last_orig)


         if not placed or not vim.startswith(placed, 'GitSignsDelete') then

            for i = last_orig + 1, last_new do
               signs.add(config, buf, { { type = 'add', count = 0, lnum = i } })
            end
            return true
         end
      end
   else


      local placed = signs.get(buf, last_orig)


      if not placed then
         signs.add(config, buf, { { type = 'change', count = 0, lnum = last_orig } })
         return true
      end
   end
end

M.on_lines = function(buf, last_orig, last_new)
   local bcache = cache[buf]
   if not bcache then
      dprint('Cache for buffer was nil. Detaching')
      return true
   end



   schedule_if_buf_valid(buf, function()
      if speculate_signs(buf, last_orig, last_new) then


















         bcache.hunks = nil
      end
   end)
   M.update_debounced(buf, cache[buf])
end

local ns = api.nvim_create_namespace('gitsigns')

M.apply_word_diff = function(bufnr, row)
   if not cache[bufnr] or not cache[bufnr].hunks then
      return
   end

   local line = api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
   if not line then

      return
   end

   local lnum = row + 1

   local hunk = gs_hunks.find_hunk(lnum, cache[bufnr].hunks)
   if not hunk then

      return
   end

   if hunk.added.count ~= hunk.removed.count then

      return
   end

   local pos = lnum - hunk.start + 1

   local added_line = hunk.added.lines[pos]
   local removed_line = hunk.removed.lines[pos]

   local _, added_regions = require('gitsigns.diff_int').run_word_diff({ removed_line }, { added_line })

   local cols = #line

   for _, region in ipairs(added_regions) do
      local rtype, scol, ecol = region[2], region[3], region[4]
      if scol <= cols then
         if ecol > cols then
            ecol = cols
         elseif ecol == scol then

            ecol = scol + 1
         end
         api.nvim_buf_set_extmark(bufnr, ns, row, scol - 1, {
            end_col = ecol - 1,
            hl_group = rtype == 'add' and 'GitSignsAddLnInline' or
            rtype == 'change' and 'GitSignsChangeLnInline' or
            'GitSignsDeleteLnInline',
            ephemeral = true,
            priority = 1000,
         })
         api.nvim__buf_redraw_range(bufnr, row, row + 1)
      end
   end
end

local ns_rm = api.nvim_create_namespace('gitsigns_removed')

local VIRT_LINE_LEN = 300

local function clear_deleted(bufnr)
   local marks = api.nvim_buf_get_extmarks(bufnr, ns_rm, 0, -1, {})
   for _, mark in ipairs(marks) do
      api.nvim_buf_del_extmark(bufnr, ns_rm, mark[1])
   end
end

local function show_deleted(bufnr)
   local bcache = cache[bufnr]

   clear_deleted(bufnr)

   if not config.show_deleted then
      return
   end

   for _, hunk in ipairs(bcache.hunks) do
      local virt_lines = {}
      local do_word_diff = config.word_diff and #hunk.removed.lines == #hunk.added.lines

      for i, line in ipairs(hunk.removed.lines) do
         local vline = {}
         local last_ecol = 1

         if do_word_diff then
            local regions = require('gitsigns.diff_int').run_word_diff(
            { hunk.removed.lines[i] }, { hunk.added.lines[i] })

            for _, region in ipairs(regions) do
               local rline, scol, ecol = region[1], region[3], region[4]
               if rline > 1 then
                  break
               end
               vline[#vline + 1] = { line:sub(last_ecol, scol - 1), 'GitsignsDeleteVirtLn' }
               vline[#vline + 1] = { line:sub(scol, ecol - 1), 'GitsignsDeleteVirtLnInline' }
               last_ecol = ecol
            end
         end

         if #line > 0 then
            vline[#vline + 1] = { line:sub(last_ecol, -1), 'GitsignsDeleteVirtLn' }
         end


         local padding = string.rep(' ', VIRT_LINE_LEN - #line)
         vline[#vline + 1] = { padding, 'GitsignsDeleteVirtLn' }

         virt_lines[i] = vline
      end

      api.nvim_buf_set_extmark(bufnr, ns_rm, hunk.start - 1, -1, {
         virt_lines = virt_lines,
         virt_lines_above = hunk.type ~= 'delete',
      })
   end
end

local update_cnt = 0

local update0 = function(bufnr, bcache)
   local __FUNC__ = 'update'
   bcache = bcache or cache[bufnr]
   if not bcache then
      eprint('Cache for buffer ' .. bufnr .. ' was nil')
      return
   end
   local old_hunks = bcache.hunks
   bcache.hunks = nil

   scheduler_if_buf_valid(bufnr)
   local buftext = util.buf_lines(bufnr)
   local git_obj = bcache.git_obj

   if not bcache.compare_text or config._refresh_staged_on_update then
      bcache.compare_text = git_obj:get_show_text(bcache:get_compare_rev())
   end

   bcache.hunks = run_diff(bcache.compare_text, buftext)

   scheduler_if_buf_valid(bufnr)
   if gs_hunks.compare_heads(bcache.hunks, old_hunks) then


      M.apply_win_signs(bufnr, bcache.hunks, vim.fn.line('w0'), vim.fn.line('w$'), true)

      show_deleted(bufnr)
   end
   local summary = gs_hunks.get_summary(bcache.hunks)
   summary.head = git_obj.repo.abbrev_head
   Status:update(bufnr, summary)

   update_cnt = update_cnt + 1

   dprintf('updates: %s, jobs: %s', update_cnt, subprocess.job_cnt)
end






M.update = throttle_by_id(update0, true)

M.setup = function()
   M.update_debounced = debounce_trailing(config.update_debounce, void(M.update))
end

M.setup_signs = function(redefine)

   for t, sign_name in pairs(signs.sign_map) do
      local cs = config.signs[t]

      signs.define(sign_name, {
         texthl = cs.hl,
         text = config.signcolumn and cs.text or nil,
         numhl = config.numhl and cs.numhl,
         linehl = config.linehl and cs.linehl,
      }, redefine)

   end
end

return M
