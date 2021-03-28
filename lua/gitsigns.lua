local gs_async = require('gitsigns/async')
local async = gs_async.async
local sync = gs_async.sync
local arun = gs_async.arun
local await = gs_async.await
local await_main = gs_async.await_main

local gs_debounce = require('gitsigns/debounce')
local debounce_trailing = gs_debounce.debounce_trailing

local gs_popup = require('gitsigns/popup')
local gs_hl = require('gitsigns/highlight')

local gs_signs = require('gitsigns/signs')
local Sign = gs_signs.Sign

local gs_config = require('gitsigns/config')
local Config = gs_config.Config

local mk_repeatable = require('gitsigns/repeat').mk_repeatable

local apply_mappings = require('gitsigns/mappings')

local git = require('gitsigns/git')
local util = require('gitsigns/util')

local gs_hunks = require("gitsigns/hunks")
local create_patch = gs_hunks.create_patch
local process_hunks = gs_hunks.process_hunks
local Hunk = gs_hunks.Hunk

local diff = require('gitsigns.diff')

local gs_debug = require("gitsigns/debug")
local dprint = gs_debug.dprint

local Status = require("gitsigns/status")

local api = vim.api
local uv = vim.loop
local current_buf = api.nvim_get_current_buf

local M

local config

local CacheEntry = {}
















local cache = {}

local function get_cache(bufnr)
   return cache[bufnr]
end

local function get_cache_opt(bufnr)
   return cache[bufnr]
end

local function get_cursor_hunk(bufnr, hunks)
   bufnr = bufnr or current_buf()
   hunks = hunks or cache[bufnr].hunks

   local lnum = api.nvim_win_get_cursor(0)[1]
   return gs_hunks.find_hunk(lnum, hunks)
end

local function remove_sign(bufnr, lnum)
   vim.fn.sign_unplace('gitsigns_ns', { buffer = bufnr, id = lnum })
end

local function add_signs(bufnr, signs)
   for lnum, s in pairs(signs) do
      local stype = gs_signs.sign_map[s.type]
      local count = s.count

      local cs = config.signs[s.type]
      if config.signcolumn and cs.show_count and count then
         local cc = config.count_chars
         local count_suffix = cc[count] and (count) or (cc['+'] and 'Plus') or ''
         local count_char = cc[count] or cc['+'] or ''
         stype = stype .. count_suffix
         gs_signs.sign_define(stype, {
            texthl = cs.hl,
            text = config.signcolumn and cs.text .. count_char or '',
            numhl = config.numhl and cs.numhl,
            linehl = config.linehl and cs.linehl,
         })
      end

      vim.fn.sign_place(lnum, 'gitsigns_ns', stype, bufnr, {
         lnum = lnum, priority = config.sign_priority,
      })
   end
end

local function apply_win_signs(bufnr, pending, top, bot)


   local first_apply = top == nil

   if config.use_decoration_api then

      top = top or tonumber(vim.fn.line('w0'))
      bot = bot or tonumber(vim.fn.line('w$'))
   else
      top = top or 0
      bot = bot or tonumber(vim.fn.line('$'))
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
      remove_sign(bufnr)





      if config.use_decoration_api then
         schedule_sign(next(pending))
      end
   end

   add_signs(bufnr, scheduled)
end

local update_cnt = 0

local update = async(function(bufnr, bcache)
   bcache = bcache or get_cache_opt(bufnr)
   if not bcache then
      error('Cache for buffer ' .. bufnr .. ' was nil')
      return
   end

   await_main()
   local buftext = api.nvim_buf_get_lines(bufnr, 0, -1, false)
   local stage = bcache.has_conflicts and 1 or 0

   if config.use_internal_diff then
      if not bcache.staged_text or config._refresh_staged_on_update then
         bcache.staged_text = await(git.get_staged_text, bcache.toplevel, bcache.relpath, stage)
      end
      bcache.hunks = diff.run_diff(bcache.staged_text, buftext, config.diff_algorithm)
   else
      await(git.get_staged, bcache.toplevel, bcache.relpath, stage, bcache.staged)
      bcache.hunks = await(git.run_diff, bcache.staged, buftext, config.diff_algorithm)
   end
   bcache.pending_signs = process_hunks(bcache.hunks)

   await_main()



   apply_win_signs(bufnr, bcache.pending_signs)

   Status:update(bufnr, gs_hunks.get_summary(bcache.hunks, bcache.abbrev_head))

   update_cnt = update_cnt + 1
   dprint(string.format('updates: %s, jobs: %s', update_cnt, util.job_cnt), bufnr, 'update')
end)


local update_debounced

local watch_index = async(function(bufnr, gitdir, on_change)
   dprint('Watching index', bufnr, 'watch_index')
   local index = gitdir .. util.path_sep .. 'index'
   local w = uv.new_fs_poll()
   w:start(index, config.watch_index.interval, on_change)
   return w
end)

local stage_hunk = sync(function()
   local bufnr = current_buf()

   local bcache = get_cache_opt(bufnr)
   if not bcache then
      return
   end

   local hunk = get_cursor_hunk(bufnr, bcache.hunks)
   if not hunk then
      return
   end

   if not util.path_exists(bcache.file) then
      print("Error: Cannot stage lines. Please add the file to the working tree.")
      return
   end

   if not bcache.object_name or bcache.has_conflicts then
      if not bcache.object_name then

         await(git.add_file, bcache.toplevel, bcache.relpath)
      else


         await(git.update_index, bcache.toplevel, bcache.mode_bits, bcache.object_name, bcache.relpath)
      end


      _, bcache.object_name, bcache.mode_bits, bcache.has_conflicts = 
      await(git.file_info, bcache.relpath, bcache.toplevel)
   end

   local lines = create_patch(bcache.relpath, hunk, bcache.mode_bits)

   await(git.stage_lines, bcache.toplevel, lines)

   table.insert(bcache.staged_diffs, hunk)

   local signs = process_hunks({ hunk })

   await_main()






   for lnum, _ in pairs(signs) do
      remove_sign(bufnr, lnum)
   end
end)

local function reset_hunk(bufnr, hunk)
   bufnr = bufnr or current_buf()

   if not hunk then
      local bcache = get_cache_opt(bufnr)
      if not bcache then
         return
      end

      hunk = get_cursor_hunk(bufnr, bcache.hunks)
   end

   if not hunk then
      return
   end

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
   api.nvim_buf_set_lines(bufnr, lstart, lend, false, gs_hunks.extract_removed(hunk))
end

local function reset_buffer()
   local bufnr = current_buf()

   local bcache = get_cache_opt(bufnr)
   if not bcache then
      return
   end

   for _, hunk in ipairs(bcache.hunks) do
      reset_hunk(bufnr, hunk)
   end
end

local undo_stage_hunk = sync(function()
   local bufnr = current_buf()

   local bcache = get_cache_opt(bufnr)
   if not bcache then
      return
   end

   local hunk = bcache.staged_diffs[#bcache.staged_diffs]

   if not hunk then
      print("No hunks to undo")
      return
   end

   local lines = create_patch(bcache.relpath, hunk, bcache.mode_bits, true)

   await(git.stage_lines, bcache.toplevel, lines)

   table.remove(bcache.staged_diffs)

   local signs = process_hunks({ hunk })

   await_main()
   add_signs(bufnr, signs)
end)

local NavHunkOpts = {}




local function nav_hunk(options)
   local bcache = get_cache_opt(current_buf())
   if not bcache then
      return
   end
   local hunks = bcache.hunks
   if not hunks or vim.tbl_isempty(hunks) then
      return
   end
   local line = api.nvim_win_get_cursor(0)[1]

   local wrap = options.wrap ~= nil and options.wrap or vim.o.wrapscan
   local hunk = gs_hunks.find_nearest_hunk(line, hunks, options.forwards, wrap)
   local row = options.forwards and hunk.start or hunk.dend
   if row then

      if row == 0 then
         row = 1
      end
      api.nvim_win_set_cursor(0, { row, 0 })
   end
end

local function next_hunk(options)
   options = options or {}
   options.forwards = true
   nav_hunk(options)
end

local function prev_hunk(options)
   options = options or {}
   options.forwards = false
   nav_hunk(options)
end







local function detach(bufnr, keep_signs)
   bufnr = bufnr or current_buf()
   dprint('Detached', bufnr)

   local bcache = get_cache_opt(bufnr)
   if not bcache then
      dprint('Cache was nil', bufnr)
      return
   end

   if not keep_signs then

      vim.fn.sign_unplace('gitsigns_ns', { buffer = bufnr })
   end


   Status:clear(bufnr)

   os.remove(bcache.staged)

   local w = bcache.index_watcher
   if w then
      w:stop()
   else
      dprint('Index_watcher was nil', bufnr)
   end

   cache[bufnr] = nil
end

local function detach_all()
   for k, _ in pairs(cache) do
      detach(k)
   end
end

local function apply_keymaps(bufonly)
   apply_mappings(config.keymaps, bufonly)
end

local function get_buf_path(bufnr)
   return
uv.fs_realpath(api.nvim_buf_get_name(bufnr)) or

   api.nvim_buf_call(bufnr, function()
      return vim.fn.expand('%:p')
   end)
end

local function index_update_handler(cbuf)
   return sync(function(err)
      if err then
         error(('Error detected in index watcher for buffer %d:\n%s'):format(cbuf, err))
      end
      dprint('Index update', cbuf, 'watcher_cb')
      local bcache = get_cache(cbuf)

      _, _, bcache.abbrev_head = 
      await(git.get_repo_info, bcache.toplevel)

      Status:update_head(cbuf, bcache.abbrev_head)

      local _, object_name0, mode_bits0, has_conflicts = 
      await(git.file_info, bcache.file, bcache.toplevel)

      if object_name0 == bcache.object_name then
         dprint('File not changed', cbuf, 'watcher_cb')
         return
      end

      bcache.object_name = object_name0
      bcache.mode_bits = mode_bits0
      bcache.has_conflicts = has_conflicts
      bcache.staged_text = nil

      await(update, cbuf, bcache)
   end)
end

local function in_git_dir(file)
   for _, p in ipairs(vim.split(file, util.path_sep)) do
      if p == '.git' then
         return true
      end
   end
   return false
end

local function on_lines(buf, last_orig, last_new)
   if not get_cache_opt(buf) then
      dprint('Cache for buffer ' .. buf .. ' was nil. Detaching')
      return true
   end



   if last_new < last_orig then
      for i = last_new + 1, last_orig do
         remove_sign(buf, i)
      end
   end

   update_debounced(buf)
end

local attach = async(function(cbuf)
   cbuf = cbuf or current_buf()
   if cache[cbuf] ~= nil then
      dprint('Already attached', cbuf, 'attach')
      return
   end
   dprint('Attaching', cbuf, 'attach')

   local lc = api.nvim_buf_line_count(cbuf)
   if lc > config.max_file_length then
      dprint('Exceeds max_file_length', cbuf, 'attach')
      return
   end

   if api.nvim_buf_get_option(cbuf, 'buftype') ~= '' then
      dprint('Non-normal buffer', cbuf, 'attach')
      return
   end

   local file = get_buf_path(cbuf)

   if in_git_dir(file) then
      dprint('In git dir', cbuf, 'attach')
      return
   end

   local file_dir = util.dirname(file)

   if not file_dir or not util.path_exists(file_dir) then
      dprint('Not a path', cbuf, 'attach')
      return
   end

   local toplevel, gitdir, abbrev_head = 
   await(git.get_repo_info, file_dir)

   if not gitdir then
      dprint('Not in git repo', cbuf, 'attach')
      return
   end

   Status:update_head(cbuf, abbrev_head)

   if not util.path_exists(file) or uv.fs_stat(file).type == 'directory' then
      dprint('Not a file', cbuf, 'attach')
      return
   end



   await_main()
   local staged = os.tmpname()

   local relpath, object_name, mode_bits, has_conflicts = 
   await(git.file_info, file, toplevel)

   if not relpath then
      dprint('Cannot resolve file in repo', cbuf, 'attach')
      return
   end

   cache[cbuf] = {
      file = file,
      relpath = relpath,
      object_name = object_name,
      mode_bits = mode_bits,
      toplevel = toplevel,
      gitdir = gitdir,
      abbrev_head = abbrev_head,
      has_conflicts = has_conflicts,
      staged = staged,
      staged_text = nil,
      hunks = {},
      staged_diffs = {},
      index_watcher = await(watch_index, cbuf, gitdir, index_update_handler(cbuf)),

   }


   await(update, cbuf, cache[cbuf])

   await_main()

   api.nvim_buf_attach(cbuf, false, {
      on_lines = function(_, buf, _, _, last_orig, last_new)
         on_lines(buf, last_orig, last_new)
      end,
      on_detach = function(_, buf)
         detach(buf, true)
      end,
   })

   apply_keymaps(true)
end)

local attach_throttled = arun(attach)

local function setup_signs(redefine)

   for t, sign_name in pairs(gs_signs.sign_map) do
      local cs = config.signs[t]

      gs_hl.setup_highlight(cs.hl)

      local HlTy = {}
      for _, hlty in ipairs({ 'numhl', 'linehl' }) do
         if config[hlty] then
            gs_hl.setup_other_highlight(cs[hlty], cs.hl)
         end
      end

      gs_signs.sign_define(sign_name, {
         texthl = cs.hl,
         text = config.signcolumn and cs.text or nil,
         numhl = config.numhl and cs.numhl,
         linehl = config.linehl and cs.linehl,
      }, redefine)

   end
end

local function add_debug_functions()
   M.dump_cache = function()
      print(vim.inspect(cache))
   end

   M.debug_messages = function()
      for _, m in ipairs(gs_debug.messages) do
         print(m)
      end
      return gs_debug.messages
   end

   M.clear_debug = function()
      gs_debug.messages = {}
   end
end


function gitsigns_complete(arglead, line)
   local n = #vim.split(line, '%s+')

   local matches = {}
   if n == 2 then
      for func, _ in pairs(M) do
         if vim.startswith(func, '_') then

         elseif vim.startswith(func, arglead) then
            table.insert(matches, func)
         end
      end
   end
   return matches
end


local function setup_command()
   vim.cmd(table.concat({
      'command!',
      '-nargs=+',
      '-complete=customlist,v:lua.gitsigns_complete',
      'Gitsigns',
      'lua require("gitsigns")._run_func(<f-args>)',
   }, ' '))
end

local setup = sync(function(cfg)
   config = gs_config.process(cfg)

   await(git.set_version, config._git_version)
   await_main()

   gs_debug.debug_mode = config.debug_mode

   if config.debug_mode then
      add_debug_functions()
   end

   Status.formatter = config.status_formatter

   setup_signs()
   setup_command()
   apply_keymaps(false)

   update_debounced = debounce_trailing(config.update_debounce, arun(update))



   vim.cmd('augroup gitsigns | autocmd! | augroup END')










   vim.cmd('autocmd gitsigns BufRead,BufNewFile,BufWritePost ' ..
   '* lua vim.schedule(require("gitsigns").attach)')

   vim.cmd('autocmd gitsigns VimLeavePre * lua require("gitsigns").detach_all()')

   vim.cmd('autocmd gitsigns ColorScheme * lua require("gitsigns")._update_highlights()')

   if config.use_decoration_api then
      local ns = api.nvim_create_namespace('gitsigns')
      api.nvim_set_decoration_provider(ns, {
         on_win = function(_, _, bufnr, top, bot)
            local bcache = get_cache_opt(bufnr)
            if not bcache or not bcache.pending_signs then
               return
            end
            apply_win_signs(bufnr, bcache.pending_signs, top, bot)
         end,
      })
   end


   for _, buf in ipairs(api.nvim_list_bufs()) do
      if api.nvim_buf_is_valid(buf) and
         api.nvim_buf_is_loaded(buf) and
         api.nvim_buf_get_name(buf) ~= '' then
         await(attach, buf)
      end
   end

end)

local function preview_hunk()
   local hunk = get_cursor_hunk()

   if not hunk then
      return
   end

   local winid, bufnr = gs_popup.create(hunk.lines, { relative = 'cursor' })

   api.nvim_buf_set_option(bufnr, 'filetype', 'diff')
   api.nvim_win_set_option(winid, 'number', false)
   api.nvim_win_set_option(winid, 'relativenumber', false)
end

local function select_hunk()
   local hunk = get_cursor_hunk()
   if not hunk then
      return
   end

   local start, dend = gs_hunks.get_range(hunk)

   vim.cmd('normal! ' .. start .. 'GV' .. dend .. 'G')
end

local blame_line = sync(function()
   local bufnr = current_buf()

   local bcache = get_cache_opt(bufnr)
   if not bcache then
      return
   end

   local buftext = api.nvim_buf_get_lines(bufnr, 0, -1, false)
   local lnum = api.nvim_win_get_cursor(0)[1]
   local result = await(git.run_blame, bcache.file, bcache.toplevel, buftext, lnum)

   local date = os.date('%Y-%m-%d %H:%M', tonumber(result['author-time']))
   local lines = {
      ('%s %s (%s):'):format(result.abbrev_sha, result.author, date),
      result.summary,
   }

   await_main()

   local winid, pbufnr = gs_popup.create(lines, { relative = 'cursor', col = 1 })

   api.nvim_win_set_option(winid, 'number', false)
   api.nvim_win_set_option(winid, 'relativenumber', false)

   local p1 = #result.abbrev_sha
   local p2 = #result.author
   local p3 = #date

   local function add_highlight(hlgroup, line, start, length)
      api.nvim_buf_add_highlight(pbufnr, -1, hlgroup, line, start, start + length)
   end

   add_highlight('Directory', 0, 0, p1)
   add_highlight('MoreMsg', 0, p1 + 1, p2)
   add_highlight('Label', 0, p1 + p2 + 2, p3 + 2)
end)

local function refresh()
   setup_signs(true)
   for k, v in pairs(cache) do
      v.staged_text = nil
      arun(update)(k, v)
   end
end

local function toggle_signs()
   config.signcolumn = not config.signcolumn
   refresh()
end

local function toggle_numhl()
   config.numhl = not config.numhl
   refresh()
end

local function toggle_linehl()
   config.linehl = not config.linehl
   refresh()
end

M = {
   update = update_debounced,
   stage_hunk = mk_repeatable(stage_hunk),
   undo_stage_hunk = mk_repeatable(undo_stage_hunk),
   reset_hunk = mk_repeatable(reset_hunk),
   next_hunk = next_hunk,
   prev_hunk = prev_hunk,
   select_hunk = select_hunk,
   preview_hunk = preview_hunk,
   blame_line = blame_line,
   reset_buffer = reset_buffer,
   attach = attach_throttled,
   detach = detach,
   detach_all = detach_all,
   setup = setup,
   refresh = refresh,
   toggle_signs = toggle_signs,
   toggle_linehl = toggle_linehl,
   toggle_numhl = toggle_numhl,

   _update_highlights = function()
      setup_signs()
   end,
   _run_func = function(func, ...)
      M[func](...)
   end,
}

return M
