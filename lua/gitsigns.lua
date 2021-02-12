local pln_cm = require('plenary/context_manager')
local with = pln_cm.with
local open = pln_cm.open

local gs_async = require('gitsigns/async')
local async = gs_async.async
local sync = gs_async.sync
local arun = gs_async.arun
local await = gs_async.await
local await_main = gs_async.await_main

local gs_debounce = require('gitsigns/debounce')
local throttle_leading = gs_debounce.throttle_leading
local debounce_trailing = gs_debounce.debounce_trailing

local gs_popup = require('gitsigns/popup')

local sign_define = require('gitsigns/signs').sign_define
local process_config = require('gitsigns/config').process
local mk_repeatable = require('gitsigns/repeat').mk_repeatable
local apply_mappings = require('gitsigns/mappings')

local git = require('gitsigns/git')
local util = require('gitsigns/util')

local gs_hunks = require("gitsigns/hunks")
local create_patch = gs_hunks.create_patch
local process_hunks = gs_hunks.process_hunks
local get_summary = gs_hunks.get_summary
local find_hunk = gs_hunks.find_hunk

local gsd = require("gitsigns/debug")
local dprint = gsd.dprint

local Status = require("gitsigns/status")

local api = vim.api
local uv = vim.loop
local current_buf = api.nvim_get_current_buf

local sign_map = {
   add = "GitSignsAdd",
   delete = "GitSignsDelete",
   change = "GitSignsChange",
   topdelete = "GitSignsTopDelete",
   changedelete = "GitSignsChangeDelete",
}

local config

local function dirname(file)
   return file:match("(.*/)")
end

local function write_to_file(file, content)
   with(open(file, 'w'), function(writer)
      for _, l in ipairs(content) do
         writer:write(l .. '\n')
      end
   end)
end

local cache = {}

local function get_cache(bufnr)
   return cache[bufnr]
end

local function get_cache_opt(bufnr)
   return cache[bufnr]
end

local function get_hunk(bufnr, hunks)
   bufnr = bufnr or current_buf()
   hunks = hunks or cache[bufnr].hunks

   local lnum = api.nvim_win_get_cursor(0)[1]
   return find_hunk(lnum, hunks)
end

local function add_signs(bufnr, signs, reset)
   reset = reset or false

   if reset then
      vim.fn.sign_unplace('gitsigns_ns', { buffer = bufnr })
   end

   for _, s in ipairs(signs) do
      local stype = sign_map[s.type]
      local count = s.count

      local cs = config.signs[s.type]
      if cs.show_count and count then
         local cc = config.count_chars
         local count_suffix = cc[count] and (count) or (cc['+'] and 'Plus') or ''
         local count_char = cc[count] or cc['+'] or ''
         stype = stype .. count_suffix
         sign_define(stype, {
            texthl = cs.hl,
            text = cs.text .. count_char,
            numhl = config.numhl and cs.numhl,
         })
      end

      vim.fn.sign_place(s.lnum, 'gitsigns_ns', stype, bufnr, {
         lnum = s.lnum, priority = config.sign_priority,
      })
   end
end

local get_staged = async(function(bufnr, staged_path, toplevel, relpath)
   await_main()
   local staged_txt = await(git.get_staged_txt, toplevel, relpath)

   if not staged_txt then
      dprint('File not in index', bufnr, 'get_staged')
      staged_txt = {}
   end

   await_main()

   write_to_file(staged_path, staged_txt)
   dprint('Updated staged file', bufnr, 'get_staged')
end)

local update_cnt = 0

local update = async(function(bufnr)
   local bcache = get_cache_opt(bufnr)
   if not bcache then
      error('Cache for buffer ' .. bufnr .. ' was nil')
      return
   end

   local relpath, toplevel, staged = 
   bcache.relpath, bcache.toplevel, bcache.staged

   await(get_staged, bufnr, staged, toplevel, relpath)

   local buftext = api.nvim_buf_get_lines(bufnr, 0, -1, false)
   bcache.hunks = await(git.run_diff, bcache.staged, buftext, config.diff_algorithm)

   local status = get_summary(bcache.hunks)
   status.head = bcache.abbrev_head

   local signs = process_hunks(bcache.hunks)

   await_main()

   add_signs(bufnr, signs, true)

   Status:update(bufnr, status)

   update_cnt = update_cnt + 1
   dprint(string.format('updates: %s, jobs: %s', update_cnt, util.job_cnt), bufnr, 'update')
end)

local update_debounced = debounce_trailing(100, arun(update))

local watch_index = async(function(bufnr, gitdir, on_change)

   dprint('Watching index', bufnr, 'watch_index')

   local index = gitdir .. '/index'
   local w = uv.new_fs_poll()
   w:start(index, config.watch_index.interval, on_change)

   return w
end)

local add_to_index = async(function(bcache)
   local relpath, toplevel = bcache.relpath, bcache.toplevel

   await_main()
   await(git.add_file, toplevel, relpath)


   await_main()
   _, bcache.object_name, bcache.mode_bits = 
   await(git.file_info, relpath, toplevel)
end)

local stage_hunk = sync(function()
   local bufnr = current_buf()

   local bcache = get_cache_opt(bufnr)
   if not bcache then
      return
   end

   local hunk = get_hunk(bufnr, bcache.hunks)
   if not hunk then
      return
   end

   if not util.path_exists(bcache.file) then
      print("Error: Cannot stage lines. Please add the file to the working tree.")
      return
   end

   if not bcache.object_name then

      await(add_to_index, bcache)
   end

   local lines = create_patch(bcache.relpath, hunk, bcache.mode_bits)

   await_main()
   await(git.stage_lines, bcache.toplevel, lines)

   table.insert(bcache.staged_diffs, hunk)

   local signs = process_hunks({ hunk })

   await_main()






   for _, s in ipairs(signs) do
      vim.fn.sign_unplace('gitsigns_ns', { buffer = bufnr, id = s.lnum })
   end
end)

local function reset_hunk()
   local bufnr = current_buf()

   local bcache = get_cache_opt(bufnr)
   if not bcache then
      return
   end

   local hunk = get_hunk(bufnr, bcache.hunks)
   if not hunk then
      return
   end

   local orig_lines = vim.tbl_map(function(l)
      return string.sub(l, 2, -1)
   end, vim.tbl_filter(function(l)
      return vim.startswith(l, '-')
   end, hunk.lines))

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
   api.nvim_buf_set_lines(bufnr, lstart, lend, false, orig_lines)
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

   await_main()
   await(git.stage_lines, bcache.toplevel, lines)

   table.remove(bcache.staged_diffs)

   local signs = process_hunks({ hunk })

   await_main()
   add_signs(bufnr, signs)
end)

local NavHunkOpts = {}




local function get_nearest_hunk_loc(lnum, hunks, forwards, wrap)
   local row
   if forwards then
      for i = 1, #hunks do
         local hunk = hunks[i]
         if hunk.start > lnum then
            row = hunk.start
            break
         end
      end
   else
      for i = #hunks, 1, -1 do
         local hunk = hunks[i]
         if hunk.dend < lnum then
            row = hunk.start
            break
         end
      end
   end
   if not row and wrap then
      row = math.max(hunks[forwards and 1 or #hunks].start, 1)
   end
   return row
end

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
   local row = get_nearest_hunk_loc(line, hunks, options.forwards, wrap)
   if row then
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

local function detach(bufnr)
   dprint('Detached', bufnr)

   local bcache = get_cache_opt(bufnr)
   if not bcache then
      dprint('Cache was nil', bufnr)
      return
   end

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
   return sync(function()
      dprint('Index update', cbuf, 'watcher_cb')
      local bcache = get_cache(cbuf)
      local file_dir = dirname(bcache.file)

      await_main()

      local _, _, abbrev_head0 = 
      await(git.get_repo_info, file_dir)

      Status:update_head(cbuf, abbrev_head0)
      bcache.abbrev_head = abbrev_head0

      await_main()

      local _, object_name0, mode_bits0 = 
      await(git.file_info, bcache.file, bcache.toplevel)

      if object_name0 == bcache.object_name then
         dprint('File not changed', cbuf, 'watcher_cb')
         return
      end

      bcache.object_name = object_name0
      bcache.mode_bits = mode_bits0

      await(update, cbuf)
   end)
end

local function in_git_dir(file)
   for _, p in ipairs(vim.split(file, '/')) do
      if p == '.git' then
         return true
      end
   end
   return false
end

local function on_lines(buf)
   if not get_cache_opt(buf) then
      dprint('Cache for buffer ' .. buf .. ' was nil. Detaching')
      return true
   end
   update_debounced(buf)
end

local attach = throttle_leading(100, sync(function()
   local cbuf = current_buf()
   if cache[cbuf] ~= nil then
      dprint('Already attached', cbuf, 'attach')
      return
   end
   dprint('Attaching', cbuf, 'attach')

   if api.nvim_buf_get_option(cbuf, 'buftype') ~= '' then
      dprint('Non-normal buffer', cbuf, 'attach')
      return
   end

   local file = get_buf_path(cbuf)

   if in_git_dir(file) then
      dprint('In git dir', cbuf, 'attach')
      return
   end

   local file_dir = dirname(file)

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
   local relpath, object_name, mode_bits = 
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
      staged = os.tmpname(),
      hunks = {},
      staged_diffs = {},
      index_watcher = await(watch_index, cbuf, gitdir, index_update_handler(cbuf)),

   }


   await(update, cbuf)

   await_main()

   api.nvim_buf_attach(cbuf, false, {
      on_lines = function(_, buf)
         on_lines(buf)
      end,
      on_detach = function(_, buf)
         detach(buf)
      end,
   })

   apply_keymaps(true)
end))

local function setup(cfg)
   config = process_config(cfg)



   gsd.debug_mode = config.debug_mode

   Status.formatter = config.status_formatter


   for t, sign_name in pairs(sign_map) do
      local cs = config.signs[t]

      if config.numhl then
         local hl_exists, _ = pcall(api.nvim_get_hl_by_name, cs.numhl, false)
         if not hl_exists then
            vim.cmd(('highlight link %s %s'):format(cs.numhl, cs.hl))
         end
      end

      sign_define(sign_name, {
         texthl = cs.hl,
         text = cs.text,
         numhl = config.numhl and cs.numhl,
      })

   end

   apply_keymaps(false)



   vim.cmd('autocmd BufRead,BufNewFile,BufWritePost ' ..
   '* lua require("gitsigns").attach()')

   vim.cmd('autocmd VimLeavePre * lua require("gitsigns").detach_all()')
end

local function preview_hunk()
   local hunk = get_hunk()

   if not hunk then
      return
   end

   local winid, bufnr = gs_popup.create(hunk.lines, { relative = 'cursor' })

   api.nvim_buf_set_option(bufnr, 'filetype', 'diff')
   api.nvim_win_set_option(winid, 'number', false)
   api.nvim_win_set_option(winid, 'relativenumber', false)
end

local function text_object()
   local hunk = get_hunk()

   if not hunk then
      return
   end

   vim.cmd('normal! ' .. hunk.start .. 'GV' .. hunk.dend .. 'G')
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

local function dump_cache()
   print(vim.inspect(cache))
end

return {
   update = update_debounced,
   stage_hunk = mk_repeatable(stage_hunk),
   undo_stage_hunk = mk_repeatable(undo_stage_hunk),
   reset_hunk = mk_repeatable(reset_hunk),
   next_hunk = next_hunk,
   prev_hunk = prev_hunk,
   preview_hunk = preview_hunk,
   blame_line = blame_line,
   attach = attach,
   detach_all = detach_all,
   setup = setup,
   text_object = text_object,
   dump_cache = dump_cache,
}
