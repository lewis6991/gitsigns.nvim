local a = require('plenary.async_lib.async')
local void = a.void
local await = a.await
local async = a.async
local async_void = a.async_void
local scheduler = a.scheduler

local gs_debounce = require('gitsigns.debounce')
local debounce_trailing = gs_debounce.debounce_trailing

local gs_hl = require('gitsigns.highlight')

local signs = require('gitsigns.signs')
local Sign = signs.Sign

local gs_config = require('gitsigns.config')
local Config = gs_config.Config

local mk_repeatable = require('gitsigns.repeat').mk_repeatable

local apply_mappings = require('gitsigns.mappings')

local git = require('gitsigns.git')
local util = require('gitsigns.util')

local gs_hunks = require("gitsigns.hunks")
local process_hunks = gs_hunks.process_hunks
local Hunk = gs_hunks.Hunk

local gs_debug = require("gitsigns.debug")
local dprint = gs_debug.dprint

local Status = require("gitsigns.status")

local api = vim.api
local uv = vim.loop
local current_buf = api.nvim_get_current_buf

local M = {}

local config

local namespace

local CacheEntry = {}











local cache = {}

local function get_cursor_hunk(bufnr, hunks)
   bufnr = bufnr or current_buf()
   hunks = hunks or cache[bufnr].hunks

   local lnum = api.nvim_win_get_cursor(0)[1]
   return gs_hunks.find_hunk(lnum, hunks)
end

local function apply_win_signs(bufnr, pending, top, bot)


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

local update_cnt = 0

local update = async(function(bufnr, bcache)
   bcache = bcache or cache[bufnr]
   if not bcache then
      error('Cache for buffer ' .. bufnr .. ' was nil')
      return
   end

   await(scheduler())
   local buftext = api.nvim_buf_get_lines(bufnr, 0, -1, false)
   local git_obj = bcache.git_obj

   local compare_object
   if bcache.commit then

      compare_object = string.format('%s^:%s', bcache.commit, git_obj.relpath)
   else
      local stage = git_obj.has_conflicts and 1 or 0
      compare_object = string.format(':%d:%s', stage, git_obj.relpath)
   end

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
   bcache.pending_signs = process_hunks(bcache.hunks)

   await(scheduler())



   apply_win_signs(bufnr, bcache.pending_signs)

   Status:update(bufnr, gs_hunks.get_summary(bcache.hunks, git_obj.abbrev_head))

   update_cnt = update_cnt + 1
   dprint(string.format('updates: %s, jobs: %s', update_cnt, util.job_cnt), bufnr, 'update')
end)


local update_debounced

local watch_index = function(bufnr, gitdir)
   dprint('Watching index', bufnr, 'watch_index')
   local index = gitdir .. util.path_sep .. 'index'
   local w = uv.new_fs_poll()
   w:start(index, config.watch_index.interval, async_void(function(err)
      if err then
         dprint('Index update error: ' .. err, bufnr, 'watcher_cb')
         return
      end
      dprint('Index update', bufnr, 'watcher_cb')

      local bcache = cache[bufnr]

      if not bcache then



         dprint(string.format('Buffer %s has detached, aborting', bufnr))
         return
      end

      local git_obj = bcache.git_obj

      await(git_obj:update_abbrev_head())

      await(scheduler())
      Status:update_head(bufnr, git_obj.abbrev_head)

      if not await(git_obj:update_file_info()) then
         dprint('File not changed', bufnr, 'watcher_cb')
         return
      end

      bcache.compare_text = nil

      await(update(bufnr, bcache))
   end))
   return w
end

local stage_hunk = async_void(function()
   local bufnr = current_buf()
   local bcache = cache[bufnr]
   if not bcache then
      return
   end

   if not util.path_exists(bcache.file) then
      print("Error: Cannot stage lines. Please add the file to the working tree.")
      return
   end

   local hunk = get_cursor_hunk(bufnr, bcache.hunks)
   if not hunk then
      return
   end

   await(bcache.git_obj:stage_hunks({ hunk }))

   table.insert(bcache.staged_diffs, hunk)
   bcache.compare_text = nil

   local hunk_signs = process_hunks({ hunk })

   await(scheduler())






   for lnum, _ in pairs(hunk_signs) do
      signs.remove(bufnr, lnum)
   end
end)

local function reset_hunk(bufnr, hunk)
   bufnr = bufnr or current_buf()
   hunk = hunk or get_cursor_hunk(bufnr)
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

local reset_buffer = async_void(function()
   local bufnr = current_buf()
   local bcache = cache[bufnr]
   if not bcache then
      return
   end

   local limit = 1000


   for _ = 1, limit do
      if not bcache.hunks[1] then
         return
      end
      reset_hunk(bufnr, bcache.hunks[1])
      await(update(bufnr, bcache))
   end
   error('Hit maximum limit of hunks to reset')
end)

local undo_stage_hunk = async_void(function()
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

   await(bcache.git_obj:stage_hunks({ hunk }, true))
   bcache.compare_text = nil
   await(scheduler())
   signs.add(config, bufnr, process_hunks({ hunk }))
end)

local stage_buffer = async_void(function()
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

   await(bcache.git_obj:stage_hunks(hunks))

   for _, hunk in ipairs(hunks) do
      table.insert(bcache.staged_diffs, hunk)
   end
   bcache.compare_text = nil

   await(scheduler())
   signs.remove(bufnr)
   Status:clear_diff(bufnr)
end)

local reset_buffer_index = async_void(function()
   local bufnr = current_buf()
   local bcache = cache[bufnr]
   if not bcache then
      return
   end







   local hunks = bcache.staged_diffs
   bcache.staged_diffs = {}

   await(bcache.git_obj:unstage_file())
   bcache.compare_text = nil

   await(scheduler())
   signs.add(config, bufnr, process_hunks(hunks))
end)

local NavHunkOpts = {}




local function nav_hunk(options)
   local bcache = cache[current_buf()]
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
   local row = options.forwards and hunk.start or hunk.vend
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
   local bcache = cache[bufnr]
   if not bcache then
      dprint('Cache was nil', bufnr)
      return
   end

   if not keep_signs then
      signs.remove(bufnr)
   end


   Status:clear(bufnr)

   os.remove(bcache.compare_file)

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
   local file = 
   uv.fs_realpath(api.nvim_buf_get_name(bufnr)) or

   api.nvim_buf_call(bufnr, function()
      return vim.fn.expand('%:p')
   end)

   if vim.startswith(file, 'fugitive://') and vim.wo.diff == false then
      local orig_path = file
      local _, _, root_path, sub_module_path, commit, real_path = 
      file:find([[^fugitive://(.*)/%.git(.*)/(%x-)/(.*)]])
      if root_path then
         sub_module_path = sub_module_path:gsub("^/modules", "")
         file = root_path .. sub_module_path .. real_path
         file = uv.fs_realpath(file)
         dprint(("Fugitive buffer for file '%s' from path '%s'"):format(file, orig_path), bufnr)
         if file then
            return file, commit
         else
            file = orig_path
         end
      end
   end

   return file
end

local function in_git_dir(file)
   for _, p in ipairs(vim.split(file, util.path_sep)) do
      if p == '.git' then
         return true
      end
   end
   return false
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

local function on_lines(buf, last_orig, last_new)
   if not cache[buf] then
      dprint('Cache for buffer ' .. buf .. ' was nil. Detaching')
      return true
   end

   speculate_signs(buf, last_orig, last_new)
   update_debounced(buf)
end

local attach = async(function(cbuf)
   await(scheduler())
   cbuf = cbuf or current_buf()
   if cache[cbuf] then
      dprint('Already attached', cbuf, 'attach')
      return
   end
   dprint('Attaching', cbuf, 'attach')

   if not api.nvim_buf_is_loaded(cbuf) then
      dprint('Non-loaded buffer', cbuf, 'attach')
      return
   end

   if api.nvim_buf_line_count(cbuf) > config.max_file_length then
      dprint('Exceeds max_file_length', cbuf, 'attach')
      return
   end

   if api.nvim_buf_get_option(cbuf, 'buftype') ~= '' then
      dprint('Non-normal buffer', cbuf, 'attach')
      return
   end

   local file, commit = get_buf_path(cbuf)

   if in_git_dir(file) then
      dprint('In git dir', cbuf, 'attach')
      return
   end

   local file_dir = util.dirname(file)

   if not file_dir or not util.path_exists(file_dir) then
      dprint('Not a path', cbuf, 'attach')
      return
   end

   local git_obj = await(git.Obj.new(file))

   if not git_obj.gitdir then
      dprint('Not in git repo', cbuf, 'attach')
      return
   end

   await(scheduler())
   Status:update_head(cbuf, git_obj.abbrev_head)

   if not util.path_exists(file) or uv.fs_stat(file).type == 'directory' then
      dprint('Not a file', cbuf, 'attach')
      return
   end

   if not git_obj.relpath then
      dprint('Cannot resolve file in repo', cbuf, 'attach')
      return
   end

   if not config.attach_to_untracked and git_obj.object_name == nil then
      dprint('File is untracked', cbuf, 'attach')
      return
   end



   await(scheduler())

   cache[cbuf] = {
      file = file,
      commit = commit,
      compare_file = os.tmpname(),
      compare_text = nil,
      hunks = {},
      staged_diffs = {},
      index_watcher = watch_index(cbuf, git_obj.gitdir),
      git_obj = git_obj,
   }


   await(update(cbuf, cache[cbuf]))

   await(scheduler())

   api.nvim_buf_attach(cbuf, false, {
      on_lines = function(_, buf, _, _, last_orig, last_new)
         return on_lines(buf, last_orig, last_new)
      end,
      on_reload = function(_, buf)
         dprint('Reload', buf, 'on_reload')
         update_debounced(buf)
      end,
      on_detach = function(_, buf)
         detach(buf, true)
      end,
   })

   apply_keymaps(true)
end)

local function setup_signs_and_highlights(redefine)

   for t, sign_name in pairs(signs.sign_map) do
      local cs = config.signs[t]

      gs_hl.setup_highlight(cs.hl)

      local HlTy = {}
      for _, hlty in ipairs({ 'numhl', 'linehl' }) do
         if config[hlty] then
            gs_hl.setup_other_highlight(cs[hlty], cs.hl)
         end
      end

      signs.define(sign_name, {
         texthl = cs.hl,
         text = config.signcolumn and cs.text or nil,
         numhl = config.numhl and cs.numhl,
         linehl = config.linehl and cs.linehl,
      }, redefine)

   end
   if config.current_line_blame then
      gs_hl.setup_highlight('GitSignsCurrentLineBlame')
   end
end


local function _complete(arglead, line)
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
      '-complete=customlist,v:lua.package.loaded.gitsigns._complete',
      'Gitsigns',
      'lua require("gitsigns")._run_func(<f-args>)',
   }, ' '))
end

local function setup_decoration_provider()
   api.nvim_set_decoration_provider(namespace, {
      on_win = function(_, _, bufnr, top, bot)
         local bcache = cache[bufnr]
         if not bcache or not bcache.pending_signs then
            return
         end
         apply_win_signs(bufnr, bcache.pending_signs, top + 1, bot + 1)
      end,
   })
end

local function setup_current_line_blame()
   vim.cmd('augroup gitsigns_blame | autocmd! | augroup END')
   if config.current_line_blame then
      for func, events in pairs({
            _current_line_blame = 'CursorHold',
            _current_line_blame_reset = 'CursorMoved',
         }) do
         vim.cmd('autocmd gitsigns_blame ' .. events .. ' * lua require("gitsigns").' .. func .. '()')
      end
   end
end

local setup = async_void(function(cfg)
   config = gs_config.build(cfg)
   namespace = api.nvim_create_namespace('gitsigns')

   gs_debug.debug_mode = config.debug_mode

   if config.debug_mode then
      for nm, f in pairs(gs_debug.add_debug_functions(cache)) do
         M[nm] = f
      end
   end

   Status.formatter = config.status_formatter

   setup_signs_and_highlights()
   setup_command()
   apply_keymaps(false)

   update_debounced = debounce_trailing(config.update_debounce, void(update))


   if config.use_decoration_api then


      setup_decoration_provider()
   end

   git.enable_yadm = config.yadm.enable
   await(git.set_version(config._git_version))
   await(scheduler())


   for _, buf in ipairs(api.nvim_list_bufs()) do
      if api.nvim_buf_is_loaded(buf) and
         api.nvim_buf_get_name(buf) ~= '' then
         await(attach(buf))
         await(scheduler())
      end
   end


   vim.cmd('augroup gitsigns | autocmd! | augroup END')

   for func, events in pairs({
         attach = 'BufRead,BufNewFile,BufWritePost',
         detach_all = 'VimLeavePre',
         _update_highlights = 'ColorScheme',
      }) do
      vim.cmd('autocmd gitsigns ' .. events .. ' * lua require("gitsigns").' .. func .. '()')
   end

   setup_current_line_blame()
end)

local function preview_hunk()
   local hunk = get_cursor_hunk()
   if not hunk then return end

   local gs_popup = require('gitsigns.popup')

   local _, bufnr = gs_popup.create(hunk.lines, config.preview_config)
   api.nvim_buf_set_option(bufnr, 'filetype', 'diff')
end

local function select_hunk()
   local hunk = get_cursor_hunk()
   if not hunk then return end

   vim.cmd('normal! ' .. hunk.start .. 'GV' .. hunk.vend .. 'G')
end

local blame_line = async_void(function()
   local bufnr = current_buf()
   local bcache = cache[bufnr]
   if not bcache then return end

   local buftext = api.nvim_buf_get_lines(bufnr, 0, -1, false)
   local lnum = api.nvim_win_get_cursor(0)[1]
   local result = await(bcache.git_obj:run_blame(buftext, lnum))

   local date = os.date('%Y-%m-%d %H:%M', tonumber(result['author_time']))
   local lines = {
      ('%s %s (%s):'):format(result.abbrev_sha, result.author, date),
      result.summary,
   }

   await(scheduler())

   local gs_popup = require('gitsigns.popup')

   local _, pbufnr = gs_popup.create(lines, config.preview_config)

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

local _current_line_blame_reset = function(bufnr)
   bufnr = bufnr or current_buf()
   api.nvim_buf_del_extmark(bufnr, namespace, 1)
end

local _current_line_blame = async_void(function()
   local bufnr = current_buf()
   local bcache = cache[bufnr]
   if not bcache or not bcache.git_obj.object_name then
      return
   end

   local buftext = api.nvim_buf_get_lines(bufnr, 0, -1, false)
   local lnum = api.nvim_win_get_cursor(0)[1]
   local result = await(bcache.git_obj:run_blame(buftext, lnum))

   await(scheduler())

   _current_line_blame_reset(bufnr)
   api.nvim_buf_set_extmark(bufnr, namespace, lnum - 1, 0, {
      id = 1,
      virt_text = config.current_line_blame_formatter(bcache.git_obj.username, result),
   })
end)

local function refresh()
   setup_signs_and_highlights(true)
   setup_current_line_blame()
   for k, v in pairs(cache) do
      _current_line_blame_reset(k)
      v.compare_text = nil
      void(update)(k, v)
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

local function toggle_current_line_blame()
   config.current_line_blame = not config.current_line_blame
   refresh()
end

M = {
   update = update_debounced,
   stage_hunk = mk_repeatable(stage_hunk),
   undo_stage_hunk = mk_repeatable(undo_stage_hunk),
   reset_hunk = mk_repeatable(reset_hunk),
   stage_buffer = stage_buffer,
   reset_buffer_index = reset_buffer_index,
   next_hunk = next_hunk,
   prev_hunk = prev_hunk,
   select_hunk = select_hunk,
   preview_hunk = preview_hunk,
   blame_line = blame_line,
   reset_buffer = reset_buffer,
   attach = void(attach),
   detach = detach,
   detach_all = detach_all,
   setup = setup,
   refresh = refresh,
   toggle_signs = toggle_signs,
   toggle_linehl = toggle_linehl,
   toggle_numhl = toggle_numhl,


   _get_config = function()
      return config
   end,

   _complete = _complete,

   _current_line_blame = _current_line_blame,
   _current_line_blame_reset = _current_line_blame_reset,
   toggle_current_line_blame = toggle_current_line_blame,

   _update_highlights = function()
      setup_signs_and_highlights()
   end,
   _run_func = function(func, ...)
      M[func](...)
   end,
}

return M
