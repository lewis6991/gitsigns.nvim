local a = require('plenary.async_lib.async')
local void = a.void
local await = a.await
local async = a.async
local async_void = a.async_void
local scheduler = a.scheduler

local sleep = require('plenary.async_lib.util').sleep

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

local CacheEntry = {Diff = {}, }


















local cache = {}

local function get_cursor_hunk(bufnr, bcache, try_sec)
   bufnr = bufnr or current_buf()
   bcache = bcache or cache[bufnr]

   local lnum = api.nvim_win_get_cursor(0)[1]

   local ret = gs_hunks.find_hunk(lnum, bcache.main.hunks)
   if not ret and try_sec then
      return gs_hunks.find_hunk(lnum, bcache.sec.hunks), true
   end
   return ret, false
end

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

local function apply_win_signs(bufnr, bcache, top, bot)
   bcache = bcache or cache[bufnr]
   if not bcache then
      return
   end



   local first_apply = top == nil

   if first_apply then
      signs.remove(bufnr, nil, true)
      signs.remove(bufnr, nil, false)
   end

   apply_win_signs0(bufnr, bcache.sec.pending_signs, top, bot, true)
   apply_win_signs0(bufnr, bcache.main.pending_signs, top, bot, false)
end

local update_cnt = 0

local function get_compare_object(base, bcache, sec)
   if sec then
      base = base or bcache.sec.base
   else
      base = base or bcache.main.base
   end
   local prefix
   if base then
      prefix = base
   elseif sec then
      prefix = 'HEAD'
   elseif bcache.commit then

      prefix = string.format('%s^', bcache.commit)
   else
      local stage = bcache.git_obj.has_conflicts and 1 or 0
      prefix = string.format(':%d', stage)
   end

   return string.format('%s:%s', prefix, bcache.git_obj.relpath)
end

local function staged_signs_enabled(c)
   return config.staged_signs and c.main.base == nil or c.sec.base ~= nil
end

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

      local compare_object = get_compare_object(o.base, bcache, sec)

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

      o.pending_signs = process_hunks(o.hunks)
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



   apply_win_signs(bufnr, bcache)

   Status:update(bufnr, gs_hunks.get_summary(bcache.main.hunks, git_obj.abbrev_head))

   update_cnt = update_cnt + 1
   dprint(string.format('updates: %s, jobs: %s', update_cnt, util.job_cnt), bufnr, 'update')
end)





local update
do
   local running = false
   local scheduled = {}
   update = async(function(bufnr)
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


local update_debounced

local watch_index = function(bufnr, gitdir)
   dprint('Watching index', bufnr, 'watch_index')
   local index = gitdir .. util.path_sep .. 'index'
   local w = uv.new_fs_poll()
   w:start(index, config.watch_index.interval, async_void(function(err)
      if err then
         dprint('Index update error: ' .. err, bufnr, 'index_watcher_cb')
         return
      end
      dprint('Index update', bufnr, 'index_watcher_cb')

      local bcache = cache[bufnr]

      if not bcache then



         dprint(string.format('Buffer %s has detached, aborting', bufnr))
         return
      end

      local git_obj = bcache.git_obj

      local old_staged_object = git_obj.staged_object

      await(git_obj:set_file_info())

      if old_staged_object == git_obj.staged_object then
         dprint('index object for file not changed', bufnr, 'index_watcher_cb')
         return
      end


      bcache.main.compare_text = nil
      bcache.sec.compare_text = nil

      await(update(bufnr))
   end))
   return w
end

local watch_head = function(bufnr, gitdir)
   dprint('Watching HEAD', bufnr, 'watch_head')

   local head = gitdir .. util.path_sep .. 'COMMIT_EDITMSG'
   local w = uv.new_fs_poll()
   w:start(head, config.watch_index.interval, async_void(function(err)
      if err then
         dprint('HEAD update error: ' .. err, bufnr, 'head_watcher_cb')
         return
      end
      dprint('HEAD update', bufnr, 'head_watcher_cb')

      local bcache = cache[bufnr]

      if not bcache then



         dprint(string.format('Buffer %s has detached, aborting', bufnr))
         return
      end

      local git_obj = bcache.git_obj

      local old_head_object = git_obj.head_object

      await(git_obj:update_head())

      await(scheduler())
      Status:update_head(bufnr, git_obj.abbrev_head)

      await(git_obj:update_head_object())

      if old_head_object == git_obj.head_object then
         dprint('HEAD object for file not changed', bufnr, 'head_watcher_cb')
         return
      end


      bcache.main.compare_text = nil
      bcache.sec.compare_text = nil

      await(update(bufnr))
   end))
   return w
end

local stage_hunk = async_void(function()
   local bufnr = current_buf()
   local bcache = cache[bufnr]
   if not bcache or bcache.main.base ~= nil then
      return
   end

   if not util.path_exists(bcache.file) then
      print("Error: Cannot stage lines. Please add the file to the working tree.")
      return
   end

   local hunk, sec = get_cursor_hunk(bufnr, bcache, true)

   if not hunk then return end
   local staged_signs_en = staged_signs_enabled(bcache)

   if sec and staged_signs_en then


      local offset = 0
      for _, h in ipairs(bcache.main.hunks) do

         if h.start > hunk.start then
            break
         end
         offset = offset - h.removed.count + h.added.count
      end
      dprint('Offset = ' .. offset, bufnr, 'stage_hunk')
      hunk.added.start = hunk.added.start - offset
   end

   await(bcache.git_obj:stage_hunks({ hunk }, sec))

   bcache.main.compare_text = nil

   local hunk_signs = process_hunks({ hunk })

   await(scheduler())






   for lnum, _ in pairs(hunk_signs) do
      signs.remove(bufnr, lnum, sec)
   end
   if staged_signs_en then
      signs.add(config, bufnr, hunk_signs, not sec)
   end
   await(update(bufnr))
end)

local function reset_hunk(bufnr, hunk)
   bufnr = bufnr or current_buf()
   hunk = hunk or get_cursor_hunk(bufnr, nil, true)

   if not hunk then return end

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
   api.nvim_buf_set_lines(bufnr, lstart, lend, false, gs_hunks.extract_lines(hunk, true))
end

local reset_buffer = async_void(function()
   local bufnr = current_buf()
   local bcache = cache[bufnr]

   if not bcache then return end

   local limit = 1000


   for _ = 1, limit do
      if not bcache.main.hunks[1] then
         return
      end
      reset_hunk(bufnr, bcache.main.hunks[1])
      await(update(bufnr))
   end
   error('Hit maximum limit of hunks to reset')
end)

local stage_buffer = async_void(function()
   local bufnr = current_buf()
   local bcache = cache[bufnr]

   if not bcache then return end

   if config.signs.base ~= nil then

      return
   end


   local hunks = bcache.main.hunks
   if #hunks == 0 then
      print("No unstaged changes in file to stage")
      return
   end

   if not util.path_exists(bcache.git_obj.file) then
      print("Error: Cannot stage file. Please add it to the working tree.")
      return
   end

   await(bcache.git_obj:stage_hunks(hunks))

   bcache.main.compare_text = nil

   await(scheduler())
   signs.remove(bufnr)
   Status:clear_diff(bufnr)
end)

local reset_buffer_index = async_void(function()
   local bufnr = current_buf()
   local bcache = cache[bufnr]

   if not bcache then return end

   await(bcache.git_obj:unstage_file())
   bcache.main.compare_text = nil

   await(scheduler())
end)

local NavHunkOpts = {}




local function nav_hunk(options)
   local bcache = cache[current_buf()]
   if not bcache then return end

   local lnum = api.nvim_win_get_cursor(0)[1]

   local wrap = options.wrap ~= nil and options.wrap or vim.o.wrapscan

   local hunks = gs_hunks.merge(bcache.main.hunks, bcache.sec.hunks)
   local hunk = gs_hunks.find_nearest_hunk(lnum, hunks, options.forwards, wrap)
   if not hunk then return end

   local row = options.forwards and hunk.start or hunk.vend


   if row == 0 then row = 1 end

   api.nvim_win_set_cursor(0, { row, 0 })
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
      signs.remove(bufnr, nil, true)
   end


   Status:clear(bufnr)

   os.remove(bcache.main.compare_file)
   os.remove(bcache.sec.compare_file)

   bcache.head_watcher:stop()
   bcache.index_watcher:stop()

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

   if vim.startswith(file, git_obj.gitdir) then
      dprint('In non-standard git dir', cbuf, 'attach')
      return
   end

   if not util.path_exists(file) or uv.fs_stat(file).type == 'directory' then
      dprint('Not a file', cbuf, 'attach')
      return
   end

   if not git_obj.relpath then
      dprint('Cannot resolve file in repo', cbuf, 'attach')
      return
   end

   if not config.attach_to_untracked and git_obj.staged_object == nil then
      dprint('File is untracked', cbuf, 'attach')
      return
   end



   await(scheduler())

   cache[cbuf] = {
      file = file,
      commit = commit,

      main = {
         compare_file = os.tmpname(),
         compare_text = nil,
         hunks = {},
         base = config.signs.base,
      },

      sec = {
         compare_file = os.tmpname(),
         compare_text = nil,
         hunks = {},
         base = config.signs_sec.base,
      },

      index_watcher = watch_index(cbuf, git_obj.gitdir),
      head_watcher = watch_head(cbuf, git_obj.gitdir),

      git_obj = git_obj,
   }


   await(update(cbuf))

   await(scheduler())

   api.nvim_buf_attach(cbuf, false, {
      on_lines = function(_, buf, _, first, last_orig, last_new, byte_count)
         if first == last_orig and last_orig == last_new and byte_count == 0 then


            return
         end
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

   for i, sign_cfg in ipairs({ config.signs, config.signs_sec }) do
      for t, sign_name in pairs(signs.sign_map) do
         local cs = sign_cfg[t]

         gs_hl.setup_highlight(cs.hl)

         local HlTy = {}
         for _, hlty in ipairs({ 'numhl', 'linehl' }) do
            if sign_cfg[hlty] and cs.hl then
               gs_hl.setup_other_highlight(cs[hlty], cs.hl)
            end
         end

         signs.define(sign_name .. (i == 2 and 'Sec' or ''), {
            texthl = cs.hl,
            text = sign_cfg.signcolumn and cs.text or nil,
            numhl = sign_cfg.numhl and cs.numhl,
            linehl = sign_cfg.linehl and cs.linehl,
         }, redefine)
      end
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
         apply_win_signs(bufnr, nil, top + 1, bot + 1)
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
   local bufnr = current_buf()
   local bcache = cache[bufnr]
   local hunk = get_cursor_hunk(bufnr, bcache, true)

   if not hunk then return end

   local gs_popup = require('gitsigns.popup')

   local _, pbufnr = gs_popup.create(hunk.lines, config.preview_config)
   api.nvim_buf_set_option(pbufnr, 'filetype', 'diff')
end

local function select_hunk()
   local bufnr = current_buf()
   local bcache = cache[bufnr]
   local hunk = get_cursor_hunk(bufnr, bcache, true)

   if not hunk then return end

   vim.cmd('normal! ' .. hunk.start .. 'GV' .. hunk.vend .. 'G')
end

local blame_line = async_void(function(full)
   local bufnr = current_buf()
   local bcache = cache[bufnr]
   if not bcache then return end

   local buftext = api.nvim_buf_get_lines(bufnr, 0, -1, false)
   local lnum = api.nvim_win_get_cursor(0)[1]
   local result = await(bcache.git_obj:run_blame(buftext, lnum))

   local gs_popup = require('gitsigns.popup')

   local is_committed = tonumber('0x' .. result.sha) ~= 0
   if is_committed then
      local body = {}
      if full then
         body = await(bcache.git_obj:command({ 'show', '-s', '--format=%b', result.sha }))

         while body[#body] == '' do
            body[#body] = nil
         end

         if #body > 0 then
            body = { '', unpack(body) }
         end
      end

      local date = os.date('%Y-%m-%d %H:%M', tonumber(result['author_time']))
      local lines = {
         ('%s %s (%s):'):format(result.abbrev_sha, result.author, date),
         result.summary,
         unpack(body),
      }

      await(scheduler())
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
   else
      local lines = { result.author }
      await(scheduler())
      local _, pbufnr = gs_popup.create(lines, config.preview_config)
      api.nvim_buf_add_highlight(pbufnr, -1, 'MoreMsg', 0, 0, #result.author)
   end
end)

local _current_line_blame_reset = function(bufnr)
   bufnr = bufnr or current_buf()
   api.nvim_buf_del_extmark(bufnr, namespace, 1)
end

local _current_line_blame = async_void(function()
   local bufnr = current_buf()
   local bcache = cache[bufnr]
   if not bcache or not bcache.git_obj.staged_object then
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
      v.main.compare_text = nil
      v.sec.compare_text = nil
      void(update)(k, v)
   end
end

local function toggle_signs(sec)
   local scfg = sec and config.signs_sec or config.signs
   scfg.signcolumn = not scfg.signcolumn
   refresh()
end

local function toggle_numhl(sec)
   local scfg = sec and config.signs_sec or config.signs
   scfg.numhl = not scfg.numhl
   refresh()
end

local function toggle_linehl(sec)
   local scfg = sec and config.signs_sec or config.signs
   scfg.linehl = not scfg.linehl
   refresh()
end

local function toggle_staged_signs()
   config.staged_signs = not config.staged_signs
   refresh()
end

local function toggle_current_line_blame()
   config.current_line_blame = not config.current_line_blame
   refresh()
end

local function calc_base(base)
   if base and base:sub(1, 1):match('[~\\^]') then
      base = 'HEAD' .. base
   end
   return base
end

local function change_base(base, sec)
   base = calc_base(base)
   local buf = current_buf()
   local obj = sec and cache[buf].sec or cache[buf].main
   obj.base = base
   obj.compare_text = nil
   update_debounced(buf)
end

local function get_show_text(bcache, comp_obj)
   if config.use_internal_diff then
      return await(bcache.git_obj:get_show_text(comp_obj))
   end

   local compare_file = os.tmpname()
   await(bcache.git_obj:get_show(comp_obj, compare_file))
   local text = util.file_lines(compare_file)
   os.remove(compare_file)
   return text
end

local function get_bcache_compare_lines(bcache)
   if config.use_internal_diff then
      return bcache.main.compare_text
   end
   return util.file_lines(bcache.main.compare_file)
end

local diffthis = async_void(function(base)
   local bufnr = current_buf()
   local bcache = cache[bufnr]
   if not bcache then return end

   if api.nvim_win_get_option(0, 'diff') then return end

   local text
   local comp_obj = get_compare_object(calc_base(base), bcache)
   if base then
      text = get_show_text(bcache, comp_obj)
   else
      text = get_bcache_compare_lines(bcache)
   end

   await(scheduler())

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

M = {
   update = update_debounced,
   stage_hunk = mk_repeatable(stage_hunk),
   reset_hunk = mk_repeatable(reset_hunk),
   stage_buffer = stage_buffer,
   reset_buffer_index = reset_buffer_index,
   reset_buffer = reset_buffer,

   next_hunk = next_hunk,
   prev_hunk = prev_hunk,
   select_hunk = select_hunk,
   preview_hunk = preview_hunk,

   blame_line = blame_line,

   change_base = change_base,
   change_sec_base = function(base) change_base(base, true) end,

   attach = void(attach),
   detach = detach,
   detach_all = detach_all,
   setup = setup,
   refresh = refresh,

   toggle_signs = toggle_signs,
   toggle_linehl = toggle_linehl,
   toggle_numhl = toggle_numhl,
   toggle_staged_signs = toggle_staged_signs,

   diffthis = diffthis,


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
