local void = require('plenary.async.async').void
local awrap = require('plenary.async.async').wrap

local gs_cache = require('gitsigns.cache')
local CacheEntry = gs_cache.CacheEntry
local cache = gs_cache.cache

local signs = require('gitsigns.signs')
local Sign = signs.Sign

local Status = require("gitsigns.status")

local debounce_trailing = require('gitsigns.debounce').debounce_trailing
local throttle_by_id = require('gitsigns.debounce').throttle_by_id
local gs_debug = require("gitsigns.debug")
local dprint = gs_debug.dprint
local dprintf = gs_debug.dprintf
local eprint = gs_debug.eprint
local subprocess = require('gitsigns.subprocess')
local util = require('gitsigns.util')

local gs_hunks = require("gitsigns.hunks")
local Hunk = gs_hunks.Hunk

local setup_highlight = require('gitsigns.highlight').setup_highlight

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

function M.apply_win_signs(bufnr, pending, top, bot)


   local first_apply = top == nil


   top = top or vim.fn.line('w0')
   bot = bot or vim.fn.line('w$')

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





      schedule_sign(next(pending))
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
         return true
      else
         local placed = signs.get(buf, last_orig)[last_orig]


         if not placed or not vim.startswith(placed, 'GitSignsDelete') then

            for i = last_orig + 1, last_new do
               signs.add(config, buf, { [i] = { type = 'add', count = 0 } })
            end
            return true
         end
      end
   else


      local placed = signs.get(buf, last_orig)[last_orig]


      if not placed then
         signs.add(config, buf, { [last_orig] = { type = 'change', count = 0 } })
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
   if not cache[bufnr] or not cache[bufnr].hunks then return end

   local lnum = row + 1
   local cols = #api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1]

   for _, hunk in ipairs(cache[bufnr].hunks) do
      if lnum >= hunk.start and lnum <= hunk.vend then
         local size = (#hunk.added.lines + #hunk.removed.lines) / 2
         local regions = require('gitsigns.diff_int').run_word_diff(hunk.removed.lines, hunk.added.lines)
         for _, region in ipairs(regions) do
            local line = region[1]
            if lnum == hunk.start + line - size - 1 then

               local rtype, scol, ecol = region[2], region[3], region[4]
               if scol <= cols then
                  if ecol > cols then
                     ecol = cols
                  elseif ecol == scol then

                     ecol = scol + 1
                  end
                  api.nvim_buf_set_extmark(bufnr, ns, row, scol - 1, {
                     end_col = ecol - 1,
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
               vline[#vline + 1] = { line:sub(last_ecol, scol - 1), config.signs.delete.linehl }
               vline[#vline + 1] = { line:sub(scol, ecol - 1), 'TermCursor' }
               last_ecol = ecol
            end
         end

         if #line > 0 then
            vline[#vline + 1] = { line:sub(last_ecol, -1), config.signs.delete.linehl }
         end


         local padding = string.rep(' ', VIRT_LINE_LEN - #line)
         vline[#vline + 1] = { padding, config.signs.delete.linehl }

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



   local run_diff
   if config.diff_opts.internal then
      run_diff = require('gitsigns.diff_int').run_diff
   else
      run_diff = require('gitsigns.diff_ext').run_diff
   end

   if not bcache.compare_text or config._refresh_staged_on_update then
      bcache.compare_text = git_obj:get_show_text(bcache:get_compare_rev())
   end

   bcache.hunks = run_diff(bcache.compare_text, buftext,
   config.diff_opts.algorithm, config.diff_opts.indent_heuristic)

   scheduler_if_buf_valid(bufnr)
   if gs_hunks.compare_heads(bcache.hunks, old_hunks) then
      bcache.pending_signs = gs_hunks.process_hunks(bcache.hunks)



      M.apply_win_signs(bufnr, bcache.pending_signs)

      show_deleted(bufnr)
   end
   local summary = gs_hunks.get_summary(bcache.hunks)
   summary.head = git_obj.repo.abbrev_head
   Status:update(bufnr, summary)

   update_cnt = update_cnt + 1

   dprintf('updates: %s, jobs: %s', update_cnt, subprocess.job_cnt)
end






M.update = throttle_by_id(update0)

M.setup = function()
   M.update_debounced = debounce_trailing(config.update_debounce, void(M.update))
end

M.setup_signs_and_highlights = function(redefine)

   for t, sign_name in pairs(signs.sign_map) do
      local cs = config.signs[t]

      setup_highlight(cs.hl)

      if config.numhl then
         setup_highlight(cs.numhl)
      end

      if config.linehl or config.word_diff then
         setup_highlight(cs.linehl)
      end

      signs.define(sign_name, {
         texthl = cs.hl,
         text = config.signcolumn and cs.text or nil,
         numhl = config.numhl and cs.numhl,
         linehl = config.linehl and cs.linehl,
      }, redefine)

   end
   if config.current_line_blame then
      setup_highlight('GitSignsCurrentLineBlame')
   end
end

return M
