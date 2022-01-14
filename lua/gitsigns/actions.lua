local void = require('plenary.async.async').void
local scheduler = require('plenary.async.util').scheduler

local Status = require("gitsigns.status")
local config = require('gitsigns.config').config
local mk_repeatable = require('gitsigns.repeat').mk_repeatable
local popup = require('gitsigns.popup')
local signs = require('gitsigns.signs')
local util = require('gitsigns.util')
local manager = require('gitsigns.manager')
local git = require('gitsigns.git')
local warn = require('gitsigns.message').warn

local gs_cache = require('gitsigns.cache')
local cache = gs_cache.cache
local CacheEntry = gs_cache.CacheEntry

local gs_hunks = require('gitsigns.hunks')
local Hunk = gs_hunks.Hunk
local Hunk_Public = gs_hunks.Hunk_Public

local api = vim.api
local current_buf = api.nvim_get_current_buf

local NavHunkOpts = {}






local M = {QFListOpts = {}, }










































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


M.toggle_deleted = function()
   config.show_deleted = not config.show_deleted
   M.refresh()
end

local function get_cursor_hunk(bufnr, hunks)
   bufnr = bufnr or current_buf()
   hunks = hunks or cache[bufnr].hunks

   local lnum = api.nvim_win_get_cursor(0)[1]
   return gs_hunks.find_hunk(lnum, hunks)
end













M.stage_hunk = mk_repeatable(void(function(range)
   range = range or M.user_range
   local bufnr = current_buf()
   local bcache = cache[bufnr]
   if not bcache then
      return
   end

   if not util.path_exists(bcache.file) then
      print("Error: Cannot stage lines. Please add the file to the working tree.")
      return
   end

   local hunk

   if range then
      table.sort(range)
      local top, bot = range[1], range[2]
      hunk = gs_hunks.create_partial_hunk(bcache.hunks, top, bot)
      hunk.added.lines = api.nvim_buf_get_lines(bufnr, top - 1, bot, false)
      hunk.removed.lines = vim.list_slice(
      bcache.compare_text,
      hunk.removed.start,
      hunk.removed.start + hunk.removed.count - 1)

   else
      hunk = get_cursor_hunk(bufnr, bcache.hunks)
   end

   if not hunk then
      return
   end

   bcache.git_obj:stage_hunks({ hunk })

   table.insert(bcache.staged_diffs, hunk)

   bcache.compare_text = nil

   local hunk_signs = gs_hunks.process_hunks({ hunk })

   scheduler()






   if not bcache.base then
      for lnum, _ in pairs(hunk_signs) do
         signs.remove(bufnr, lnum)
      end
   end
   void(manager.update)(bufnr)
end))










M.reset_hunk = mk_repeatable(function(range)
   range = range or M.user_range
   local bufnr = current_buf()
   local bcache = cache[bufnr]
   if not bcache then
      return
   end

   local hunk

   if range then
      table.sort(range)
      local top, bot = range[1], range[2]
      hunk = gs_hunks.create_partial_hunk(bcache.hunks, top, bot)
      hunk.added.lines = api.nvim_buf_get_lines(bufnr, top - 1, bot, false)
      hunk.removed.lines = vim.list_slice(
      bcache.compare_text,
      hunk.removed.start,
      hunk.removed.start + hunk.removed.count - 1)

   else
      hunk = get_cursor_hunk(bufnr)
   end

   if not hunk then
      return
   end

   local lstart, lend
   if hunk.type == 'delete' then
      lstart = hunk.start
      lend = hunk.start
   else
      lstart = hunk.start - 1
      lend = hunk.start - 1 + hunk.added.count
   end
   local lines = hunk.removed.lines
   api.nvim_buf_set_lines(bufnr, lstart, lend, false, lines)
end)


M.reset_buffer = function()
   local bufnr = current_buf()
   local bcache = cache[bufnr]
   if not bcache then
      return
   end

   api.nvim_buf_set_lines(bufnr, 0, -1, false, bcache:get_compare_text())
end








M.undo_stage_hunk = void(function()
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
   if not bcache.base then
      signs.add(config, bufnr, gs_hunks.process_hunks({ hunk }))
   end
   manager.update(bufnr)
end)





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
   if not bcache.base then
      signs.remove(bufnr)
   end
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
   if not bcache.base then
      signs.add(config, bufnr, gs_hunks.process_hunks(hunks))
   end
   void(manager.update)(bufnr)
end)

local function process_nav_opts(opts)

   if opts.navigation_message == nil then
      opts.navigation_message = not vim.opt.shortmess:get().S
   end


   if opts.wrap == nil then
      opts.wrap = vim.opt.wrapscan:get()
   end

   if opts.foldopen == nil then
      opts.foldopen = vim.tbl_contains(vim.opt.foldopen:get(), 'search')
   end
end

local function nav_hunk(opts)
   process_nav_opts(opts)
   local bcache = cache[current_buf()]
   if not bcache then
      return
   end

   local hunks = bcache.hunks
   if not hunks or vim.tbl_isempty(hunks) then
      if opts.navigation_message then
         vim.api.nvim_echo({ { 'No hunks', 'WarningMsg' } }, false, {})
      end
      return
   end
   local line = api.nvim_win_get_cursor(0)[1]

   local hunk, index = gs_hunks.find_nearest_hunk(line, hunks, opts.forwards, opts.wrap)

   if hunk == nil then
      if opts.navigation_message then
         vim.api.nvim_echo({ { 'No more hunks', 'WarningMsg' } }, false, {})
      end
      return
   end

   local row = opts.forwards and hunk.start or hunk.vend
   if row then

      if row == 0 then
         row = 1
      end
      vim.cmd([[ normal! m' ]])
      api.nvim_win_set_cursor(0, { row, 0 })
      if opts.foldopen then
         vim.cmd('silent! foldopen!')
      end
      if pcall(api.nvim_buf_get_var, 0, '_gitsigns_preview_open') then
         vim.schedule(M.preview_hunk)
      end

      if index ~= nil and opts.navigation_message then
         vim.api.nvim_echo({ { string.format('Hunk %d of %d', index, #hunks), 'None' } }, false, {})
      end

   end
end















M.next_hunk = function(opts)
   opts = opts or {}
   opts.forwards = true
   nav_hunk(opts)
end





M.prev_hunk = function(opts)
   opts = opts or {}
   opts.forwards = false
   nav_hunk(opts)
end

local function highlight_hunk_lines(bufnr, offset, hunk)
   for i = 1, #hunk.removed.lines do
      api.nvim_buf_add_highlight(bufnr, -1, 'DiffRemoved', offset + i - 1, 0, -1)
   end
   for i = 1, #hunk.added.lines do
      api.nvim_buf_add_highlight(bufnr, -1, 'DiffAdded', #hunk.removed.lines + offset + i - 1, 0, -1)
   end

   if config.diff_opts.internal then
      local regions = require('gitsigns.diff_int').run_word_diff(hunk.removed.lines, hunk.added.lines)
      for _, region in ipairs(regions) do
         local line, scol, ecol = region[1], region[3], region[4]
         api.nvim_buf_add_highlight(bufnr, -1, 'TermCursor', line + offset - 1, scol, ecol)
      end
   end
end

local function noautocmd(f)
   return function()
      local ei = api.nvim_get_option('eventignore')
      api.nvim_set_option('eventignore', 'all')
      f()
      api.nvim_set_option('eventignore', ei)
   end
end


local function strip_cr(xs0)
   for i = 1, #xs0 do
      if xs0[i]:sub(-1) ~= '\r' then

         return xs0
      end
   end

   local xs = vim.deepcopy(xs0)
   for i = 1, #xs do
      xs[i] = xs[i]:sub(1, -2)
   end
   return xs
end



M.preview_hunk = noautocmd(function()

   local cbuf = current_buf()
   local bcache = cache[cbuf]
   local hunk, index = get_cursor_hunk(cbuf, bcache.hunks)

   if not hunk then return end

   local hlines = gs_hunks.patch_lines(hunk)
   if vim.bo[cbuf].fileformat == 'dos' then
      hlines = strip_cr(hlines)
   end

   local lines = {
      ('Hunk %d of %d'):format(index, #bcache.hunks),
      unpack(hlines),
   }

   local _, bufnr = popup.create(lines, config.preview_config)

   api.nvim_buf_add_highlight(bufnr, -1, 'Title', 0, 0, -1)

   api.nvim_buf_set_var(cbuf, '_gitsigns_preview_open', true)
   vim.cmd([[autocmd CursorMoved,CursorMovedI <buffer> ++once silent! unlet b:_gitsigns_preview_open]])

   local offset = #lines - hunk.removed.count - hunk.added.count
   highlight_hunk_lines(bufnr, offset, hunk)
end)


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
         lines = gs_hunks.patch_lines(h),
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
   local diff_opts = config.diff_opts
   local f
   if config.diff_opts.internal then
      f = require('gitsigns.diff_int').run_diff
   else
      f = require('gitsigns.diff_ext').run_diff
   end
   return f(a, b, diff_opts.algorithm, diff_opts.indent_heuristic)
end

local function get_blame_hunk(repo, info)
   local a = {}

   if info.previous then
      a = repo:get_show_text(info.previous_sha .. ':' .. info.previous_filename)
   end
   local b = repo:get_show_text(info.sha .. ':' .. info.filename)
   local hunks = run_diff(a, b)
   local hunk, i = gs_hunks.find_hunk(info.orig_lnum, hunks)
   return hunk, i, #hunks
end

local BlameOpts = {}

















M.blame_line = void(function(opts)
   local bufnr = current_buf()
   local bcache = cache[bufnr]
   if not bcache then return end

   local full
   local ignore_whitespace
   if type(opts) == "boolean" then

      warn('Passing boolean as the first argument to blame_line is now deprecated; please pass an options table')
      full = opts
   else
      opts = opts or {}
      full = opts.full
      ignore_whitespace = opts.ignore_whitespace
   end

   local loading = defer(1000, function()
      popup.create({ 'Loading...' }, config.preview_config)
   end)

   scheduler()
   local buftext = util.buf_lines(bufnr)
   local lnum = api.nvim_win_get_cursor(0)[1]
   local result = bcache.git_obj:run_blame(buftext, lnum, ignore_whitespace)
   pcall(function()
      loading:close()
   end)

   local hunk, ihunk, nhunk
   local lines = {}

   local highlights = {}

   local function add_highlight(hlgroup, start, length)
      highlights[#highlights + 1] = { hlgroup, #lines - 1, start or 0, length or -1 }
   end

   local is_committed = result.sha and tonumber('0x' .. result.sha) ~= 0
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
         hunk, ihunk, nhunk = get_blame_hunk(bcache.git_obj.repo, result)
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
      vim.list_extend(lines, gs_hunks.patch_lines(hunk))
   end

   scheduler()
   local _, pbufnr = popup.create(lines, config.preview_config)

   for _, h in ipairs(highlights) do
      local hlgroup, line, start, length = h[1], h[2], h[3], h[4]
      api.nvim_buf_add_highlight(pbufnr, -1, hlgroup, line, start, start + length)
   end

   if hunk then
      local offset = #lines - hunk.removed.count - hunk.added.count
      highlight_hunk_lines(pbufnr, offset, hunk)
   end
end)

local function calc_base(base)
   if base and base:sub(1, 1):match('[~\\^]') then
      base = 'HEAD' .. base
   end
   return base
end

local function update_buf_base(buf, bcache, base)
   bcache.base = base
   bcache.compare_text = nil
   manager.update(buf, bcache)
end


































M.change_base = void(function(base, global)
   base = calc_base(base)

   if global then
      config.base = base

      for buf, bcache in pairs(cache) do
         update_buf_base(buf, bcache, base)
      end
   else
      local buf = current_buf()
      local bcache = cache[buf]
      if not bcache then return end

      update_buf_base(buf, bcache, base)
   end
end)





M.reset_base = function(global)
   M.change_base(nil, global)
end

















M.diffthis = void(function(base)
   local bufnr = current_buf()
   local bcache = cache[bufnr]
   if not bcache then return end

   if api.nvim_win_get_option(0, 'diff') then return end

   local ff = vim.bo[bufnr].fileformat

   local text
   local err
   local comp_rev = bcache:get_compare_rev(calc_base(base))

   if base then
      text, err = bcache.git_obj:get_show_text(comp_rev)
      if ff == 'dos' then
         text = strip_cr(text)
      end
      if err then
         print(err)
         return
      end
      scheduler()
   else
      text = bcache:get_compare_text()
   end

   local ft = api.nvim_buf_get_option(bufnr, 'filetype')

   local bufname = string.format(
   'gitsigns://%s/%s',
   bcache.git_obj.repo.gitdir,
   comp_rev .. ':' .. bcache.git_obj.relpath)



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
   elseif target == 'attached' then
      for bufnr, bcache in pairs(cache) do
         hunks_to_qflist(bufnr, bcache.hunks, qflist)
      end
   elseif target == 'all' then
      local repos = {}
      for _, bcache in pairs(cache) do
         local repo = bcache.git_obj.repo
         if not repos[repo.gitdir] then
            repos[repo.gitdir] = repo
         end
      end

      local repo = git.Repo.new(vim.fn.getcwd())
      if not repos[repo.gitdir] then
         repos[repo.gitdir] = repo
      end

      for _, r in pairs(repos) do
         for _, f in ipairs(r:files_changed()) do
            local f_abs = r.toplevel .. '/' .. f
            local stat = vim.loop.fs_stat(f_abs)
            if stat and stat.type == 'file' then
               local a = r:get_show_text(':0:' .. f)
               scheduler()
               local hunks = run_diff(a, util.file_lines(f_abs))
               hunks_to_qflist(f_abs, hunks, qflist)
            end
         end
      end

   end
   return qflist
end





























M.setqflist = void(function(target, opts)
   opts = opts or {}
   if opts.open == nil then
      opts.open = true
   end
   local qfopts = {
      items = buildqflist(target),
      title = 'Hunks',
   }
   scheduler()
   if opts.use_location_list then
      local nr = opts.nr or 0
      vim.fn.setloclist(nr, {}, ' ', qfopts)
      if opts.open then
         if config.trouble then
            require('trouble').open("loclist")
         else
            vim.cmd([[lopen]])
         end
      end
   else
      vim.fn.setqflist({}, ' ', qfopts)
      if opts.open then
         if config.trouble then
            require('trouble').open("quickfix")
         else
            vim.cmd([[copen]])
         end
      end
   end
end)













M.setloclist = function(nr, target)
   M.setqflist(target, {
      nr = nr,
      use_location_list = true,
   })
end







M.get_actions = function()
   local bufnr = current_buf()
   local bcache = cache[bufnr]
   if not bcache then
      return
   end
   local hunk = get_cursor_hunk(bufnr, bcache.hunks)

   local actions_l = {}

   local function add_action(action)
      actions_l[#actions_l + 1] = action
   end

   if hunk then
      add_action('stage_hunk')
      add_action('reset_hunk')
      add_action('preview_hunk')
      add_action('select_hunk')
   else
      add_action('blame_line')
   end

   if not vim.tbl_isempty(bcache.staged_diffs) then
      add_action('undo_stage_hunk')
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

return M
