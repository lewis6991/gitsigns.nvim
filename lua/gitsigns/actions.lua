local void = require('plenary.async.async').void
local scheduler = require('plenary.async.util').scheduler
local will_block = require('plenary.async.util').will_block

local Status = require("gitsigns.status")
local config = require('gitsigns.config').config
local mk_repeatable = require('gitsigns.repeat').mk_repeatable
local popup = require('gitsigns.popup')
local signs = require('gitsigns.signs')
local util = require('gitsigns.util')
local manager = require('gitsigns.manager')
local git = require('gitsigns.git')

local gs_cache = require('gitsigns.cache')
local cache = gs_cache.cache
local CacheEntry = gs_cache.CacheEntry

local gs_hunks = require('gitsigns.hunks')
local Hunk = gs_hunks.Hunk

local api = vim.api
local current_buf = api.nvim_get_current_buf

local NavHunkOpts = {}





local M = {}

































local function get_cursor_hunk(bufnr, hunks)
   bufnr = bufnr or current_buf()
   hunks = hunks or cache[bufnr].hunks

   local lnum = api.nvim_win_get_cursor(0)[1]
   return gs_hunks.find_hunk(lnum, hunks)
end







local function get_range_hunks(bufnr, hunks, range, strict)
   bufnr = bufnr or current_buf()
   hunks = hunks or cache[bufnr].hunks

   local ret = {}
   for _, hunk in ipairs(hunks) do
      if range[1] == 1 and hunk.start == 0 and hunk.vend == 0 then
         return { hunk }
      end

      if strict then
         if (range[1] <= hunk.start and range[2] >= hunk.vend) then
            ret[#ret + 1] = hunk
         end
      else
         if (range[2] >= hunk.start and range[1] <= hunk.vend) then
            ret[#ret + 1] = hunk
         end
      end
   end

   return ret
end

M.stage_hunk = mk_repeatable(void(function(range)
   range = range or M.user_range
   local valid_range = false
   local bufnr = current_buf()
   local bcache = cache[bufnr]
   if not bcache then
      return
   end

   if not util.path_exists(bcache.file) then
      print("Error: Cannot stage lines. Please add the file to the working tree.")
      return
   end

   local hunks = {}

   if range and range[1] ~= range[2] then
      valid_range = true
      table.sort(range)
      hunks = get_range_hunks(bufnr, bcache.hunks, range)
   else
      hunks[1] = get_cursor_hunk(bufnr, bcache.hunks)
   end

   if #hunks == 0 then
      return
   end

   bcache.git_obj:stage_hunks(hunks)

   for _, hunk in ipairs(hunks) do
      table.insert(bcache.staged_diffs, hunk)
   end

   bcache.compare_text = nil

   local hunk_signs = gs_hunks.process_hunks(hunks)

   scheduler()






   for lnum, _ in pairs(hunk_signs) do
      signs.remove(bufnr, lnum)
   end
   void(manager.update)(bufnr)
end))

M.reset_hunk = mk_repeatable(function(range)
   range = range or M.user_range
   local bufnr = current_buf()
   local hunks = {}

   if range and range[1] ~= range[2] then
      table.sort(range)
      hunks = get_range_hunks(bufnr, nil, range)
   else
      hunks[1] = get_cursor_hunk(bufnr)
   end

   if #hunks == 0 then
      return
   end

   local offset = 0

   for _, hunk in ipairs(hunks) do
      local lstart, lend
      if hunk.type == 'delete' then
         lstart = hunk.start
         lend = hunk.start
      else
         local length = vim.tbl_count(vim.tbl_filter(function(l)
            return vim.startswith(l, '+')
         end, hunk.lines))

         lstart = hunk.start - 1
         lend = hunk.start - 1 + length
      end
      local lines = gs_hunks.extract_removed(hunk)
      api.nvim_buf_set_lines(bufnr, lstart + offset, lend + offset, false, lines)
      offset = offset + (#lines - (lend - lstart))
   end
end)

M.reset_buffer = function()
   local bufnr = current_buf()
   local bcache = cache[bufnr]
   if not bcache then
      return
   end

   api.nvim_buf_set_lines(bufnr, 0, -1, false, bcache:get_compare_text())
end

M.undo_stage_hunk = mk_repeatable(void(function()
   local bufnr = current_buf()
   local bcache = cache[bufnr]
   if not bcache then
      return
   end

   local hunk = table.remove(bcache.staged_diffs)
   if not hunk then
      print("No hunks to undo")
      return
   end

   bcache.git_obj:stage_hunks({ hunk }, true)
   bcache.compare_text = nil
   scheduler()
   signs.add(config, bufnr, gs_hunks.process_hunks({ hunk }))
   manager.update(bufnr)
end))

M.stage_buffer = void(function()
   local bufnr = current_buf()

   local bcache = cache[bufnr]
   if not bcache then
      return
   end


   local hunks = bcache.hunks
   if #hunks == 0 then
      print("No unstaged changes in file to stage")
      return
   end

   if not util.path_exists(bcache.git_obj.file) then
      print("Error: Cannot stage file. Please add it to the working tree.")
      return
   end

   bcache.git_obj:stage_hunks(hunks)

   for _, hunk in ipairs(hunks) do
      table.insert(bcache.staged_diffs, hunk)
   end
   bcache.compare_text = nil

   scheduler()
   signs.remove(bufnr)
   Status:clear_diff(bufnr)
end)

M.reset_buffer_index = void(function()
   local bufnr = current_buf()
   local bcache = cache[bufnr]
   if not bcache then
      return
   end







   local hunks = bcache.staged_diffs
   bcache.staged_diffs = {}

   bcache.git_obj:unstage_file()
   bcache.compare_text = nil

   scheduler()
   signs.add(config, bufnr, gs_hunks.process_hunks(hunks))
   void(manager.update)(bufnr)
end)

local function nav_hunk(options)
   local bcache = cache[current_buf()]
   if not bcache then
      return
   end


   local show_navigation_msg = not string.find(vim.o.shortmess, 'S')
   if options.navigation_message ~= nil then
      show_navigation_msg = options.navigation_message
   end

   local hunks = bcache.hunks
   if not hunks or vim.tbl_isempty(hunks) then
      if show_navigation_msg then
         vim.api.nvim_echo({ { 'No hunks', 'WarningMsg' } }, false, {})
      end
      return
   end
   local line = api.nvim_win_get_cursor(0)[1]


   local wrap = vim.o.wrapscan
   if options.wrap ~= nil then
      wrap = options.wrap
   end

   local hunk, index = gs_hunks.find_nearest_hunk(line, hunks, options.forwards, wrap)

   if hunk == nil then
      if show_navigation_msg then
         vim.api.nvim_echo({ { 'No more hunks', 'WarningMsg' } }, false, {})
      end
      return
   end

   local row = options.forwards and hunk.start or hunk.vend
   if row then

      if row == 0 then
         row = 1
      end
      api.nvim_win_set_cursor(0, { row, 0 })
      if pcall(api.nvim_buf_get_var, 0, '_gitsigns_preview_open') then
         vim.schedule(M.preview_hunk)
      end

      if index ~= nil and show_navigation_msg then
         vim.api.nvim_echo({ { string.format('Hunk %d of %d', index, #hunks), 'None' } }, false, {})
      end

   end
end

M.next_hunk = function(options)
   options = options or {}
   options.forwards = true
   nav_hunk(options)
end

M.prev_hunk = function(options)
   options = options or {}
   options.forwards = false
   nav_hunk(options)
end

local function highlight_hunk_lines(bufnr, offset, hunk_lines)
   for i, l in ipairs(hunk_lines) do
      local hl = 
      vim.startswith(l, '+') and 'DiffAdded' or
      vim.startswith(l, '-') and 'DiffRemoved' or
      'Normal'
      api.nvim_buf_add_highlight(bufnr, -1, hl, offset + i - 1, 0, -1)
   end

   if config.use_internal_diff then
      local regions = require('gitsigns.diff_int').run_word_diff(hunk_lines)
      for _, region in ipairs(regions) do
         local line, scol, ecol = region[1], region[3], region[4]
         api.nvim_buf_add_highlight(bufnr, -1, 'TermCursor', line + offset - 1, scol, ecol)
      end
   end
end

M.preview_hunk = function()
   local cbuf = current_buf()
   local bcache = cache[cbuf]
   local hunk, index = get_cursor_hunk(cbuf, bcache.hunks)

   if not hunk then return end

   local lines = {
      ('Hunk %d of %d'):format(index, #bcache.hunks),
      unpack(hunk.lines),
   }

   local _, bufnr = popup.create(lines, config.preview_config)

   api.nvim_buf_add_highlight(bufnr, -1, 'Title', 0, 0, -1)

   api.nvim_buf_set_var(cbuf, '_gitsigns_preview_open', true)
   vim.cmd([[autocmd CursorMoved,CursorMovedI <buffer> ++once silent! unlet b:_gitsigns_preview_open]])

   local offset = #lines - #hunk.lines
   highlight_hunk_lines(bufnr, offset, hunk.lines)
end

M.select_hunk = function()
   local hunk = get_cursor_hunk()
   if not hunk then return end

   vim.cmd('normal! ' .. hunk.start .. 'GV' .. hunk.vend .. 'G')
end

M.get_hunks = function(bufnr)
   bufnr = current_buf()
   if not cache[bufnr] then return end
   local ret = {}
   for _, h in ipairs(cache[bufnr].hunks) do
      ret[#ret + 1] = {
         head = h.head,
         lines = h.lines,
         type = h.type,
         added = h.added,
         removed = h.removed,
      }
   end
   return ret
end

local function defer(duration, callback)
   local timer = vim.loop.new_timer()
   timer:start(duration, 0, function()
      timer:stop()
      timer:close()
      vim.schedule_wrap(callback)()
   end)
   return timer
end

local function run_diff(a, b)
   if config.use_internal_diff then
      return require('gitsigns.diff_int').run_diff(a, b, config.diff_algorithm)
   else
      return require('gitsigns.diff_ext').run_diff(a, b, config.diff_algorithm)
   end
end

local function get_blame_hunk(git_obj, info)
   local a = {}

   if info.previous then
      a = git_obj:get_show_text(info.previous_sha .. ':' .. info.previous_filename)
   end
   local b = git_obj:get_show_text(info.sha .. ':' .. info.filename)
   local hunks = run_diff(a, b)
   local hunk, i = gs_hunks.find_hunk(info.orig_lnum, hunks)
   return hunk, i, #hunks
end

M.blame_line = void(function(full)
   local bufnr = current_buf()
   local bcache = cache[bufnr]
   if not bcache then return end

   local loading = defer(1000, function()
      popup.create({ 'Loading...' }, config.preview_config)
   end)

   scheduler()
   local buftext = api.nvim_buf_get_lines(bufnr, 0, -1, false)
   local lnum = api.nvim_win_get_cursor(0)[1]
   local result = bcache.git_obj:run_blame(buftext, lnum)
   pcall(function()
      loading:close()
   end)

   local hunk, ihunk, nhunk
   local lines = {}

   local highlights = {}

   local function add_highlight(hlgroup, start, length)
      highlights[#highlights + 1] = { hlgroup, #lines - 1, start or 0, length or -1 }
   end

   local is_committed = bcache.git_obj.object_name and tonumber('0x' .. result.sha) ~= 0
   if is_committed then
      local commit_message = {}
      if full then
         commit_message = bcache.git_obj:command({ 'show', '-s', '--format=%B', result.sha })
         while commit_message[#commit_message] == '' do
            commit_message[#commit_message] = nil
         end
      else
         commit_message = { result.summary }
      end

      local date = os.date('%Y-%m-%d %H:%M', tonumber(result['author_time']))

      lines[#lines + 1] = ('%s %s (%s):'):format(result.abbrev_sha, result.author, date)
      local p1 = #result.abbrev_sha
      local p2 = #result.author
      local p3 = #date

      add_highlight('Directory', 0, p1)
      add_highlight('MoreMsg', p1 + 1, p2)
      add_highlight('Label', p1 + p2 + 2, p3 + 2)

      vim.list_extend(lines, commit_message)

      if full then
         hunk, ihunk, nhunk = get_blame_hunk(bcache.git_obj, result)
      end
   else
      lines[#lines + 1] = result.author
      add_highlight('ErrorMsg')
      if full then
         scheduler()
         hunk, ihunk = get_cursor_hunk(bufnr, bcache.hunks)
         nhunk = #bcache.hunks
      end
   end

   if hunk then
      lines[#lines + 1] = ''
      lines[#lines + 1] = ('Hunk %d of %d'):format(ihunk, nhunk)
      add_highlight('Title')
      vim.list_extend(lines, hunk.lines)
   end

   scheduler()
   local _, pbufnr = popup.create(lines, config.preview_config)

   for _, h in ipairs(highlights) do
      local hlgroup, line, start, length = h[1], h[2], h[3], h[4]
      api.nvim_buf_add_highlight(pbufnr, -1, hlgroup, line, start, start + length)
   end

   if hunk then
      local offset = #lines - #hunk.lines
      highlight_hunk_lines(pbufnr, offset, hunk.lines)
   end
end)

local function calc_base(base)
   if base and base:sub(1, 1):match('[~\\^]') then
      base = 'HEAD' .. base
   end
   return base
end

M.change_base = function(base)
   local buf = current_buf()
   local bcache = cache[buf]
   if bcache == nil then return end
   base = calc_base(base)
   bcache.base = base
   bcache.compare_text = nil
   void(manager.update)(buf, bcache)
end

M.diffthis = void(function(base)
   local bufnr = current_buf()
   local bcache = cache[bufnr]
   if not bcache then return end

   if api.nvim_win_get_option(0, 'diff') then return end

   local text
   local err
   local comp_obj = bcache:get_compare_obj(calc_base(base))
   if base then
      text, err = bcache.git_obj:get_show_text(comp_obj)
      if err then
         print(err)
         return
      end
      scheduler()
   else
      text = bcache:get_compare_text()
   end

   local ft = api.nvim_buf_get_option(bufnr, 'filetype')

   local bufname = string.format('gitsigns://%s/%s', bcache.git_obj.gitdir, comp_obj)


   vim.cmd("keepalt aboveleft vertical split " .. bufname)

   local dbuf = current_buf()

   api.nvim_buf_set_option(dbuf, 'modifiable', true)
   api.nvim_buf_set_lines(dbuf, 0, -1, false, text)
   api.nvim_buf_set_option(dbuf, 'modifiable', false)

   api.nvim_buf_set_option(dbuf, 'filetype', ft)
   api.nvim_buf_set_option(dbuf, 'buftype', 'nowrite')

   vim.cmd(string.format('autocmd! WinClosed <buffer=%d> ++once call nvim_buf_delete(%d, {})', dbuf, dbuf))

   vim.cmd([[windo diffthis]])
end)

local function hunks_to_qflist(buf_or_filename, hunks, qflist)
   for i, hunk in ipairs(hunks) do
      qflist[#qflist + 1] = {
         bufnr = type(buf_or_filename) == "number" and (buf_or_filename) or nil,
         filename = type(buf_or_filename) == "string" and buf_or_filename or nil,
         lnum = hunk.start,
         text = string.format('Lines %d-%d (%d/%d)',
         hunk.start, hunk.vend, i, #hunks),
      }
   end
end

local function buildqflist(target)
   target = target or current_buf()
   if target == 0 then target = current_buf() end
   local qflist = {}

   if type(target) == 'number' then
      local bufnr = target
      if not cache[bufnr] then return end
      hunks_to_qflist(bufnr, cache[bufnr].hunks, qflist)
   elseif target == 'attached' or target == 'all' then
      local gitdirs_done = {}
      for bufnr, bcache in pairs(cache) do
         hunks_to_qflist(bufnr, bcache.hunks, qflist)

         if target == 'all' then
            local git_obj = bcache.git_obj
            if not gitdirs_done[git_obj.gitdir] then
               for _, f in ipairs(git_obj:files_changed()) do
                  local f_abs = git_obj.toplevel .. '/' .. f
                  local hunks = run_diff(
                  git_obj:get_show_text(':0:' .. f),
                  util.file_lines(f_abs))

                  hunks_to_qflist(f_abs, hunks, qflist)
               end
            end
            gitdirs_done[git_obj.gitdir] = true
         end
      end
   end
   return qflist
end

M.setqflist = will_block(function(target)
   local qflist = buildqflist(target)
   scheduler()
   vim.fn.setqflist({}, ' ', {
      items = qflist,
      title = 'Hunks',
   })
end)

M.setloclist = will_block(function(nr, target)
   nr = nr or 0
   local qflist = buildqflist(target)
   scheduler()
   vim.fn.setloclist(nr, {}, ' ', {
      items = qflist,
      title = 'Hunks',
   })
end)

M.get_actions = function()
   local hunk = get_cursor_hunk()










   local actions_l = {}
   if hunk then
      actions_l = {
         'stage_hunk',
         'undo_stage_hunk',
         'reset_hunk',
         'preview_hunk',
         'select_hunk',
      }
   else
      actions_l = {
         'blame_line',
      }
   end

   local actions = {}
   for _, a in ipairs(actions_l) do
      actions[a] = (M)[a]
   end

   return actions
end

M.refresh = void(function()
   manager.setup_signs_and_highlights(true)
   require('gitsigns.current_line_blame').setup()
   for k, v in pairs(cache) do

      v.compare_text = nil
      v.hunks = nil
      manager.update(k, v)
   end
end)

M.toggle_signs = function()
   config.signcolumn = not config.signcolumn
   M.refresh()
end

M.toggle_numhl = function()
   config.numhl = not config.numhl
   M.refresh()
end

M.toggle_linehl = function()
   config.linehl = not config.linehl
   M.refresh()
end

M.toggle_word_diff = function()
   config.word_diff = not config.word_diff
   M.refresh()
end

M.toggle_current_line_blame = function()
   config.current_line_blame = not config.current_line_blame
   M.refresh()
end

return M
