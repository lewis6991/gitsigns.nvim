local Job = require('plenary/job')

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

local gs_hunks = require("gitsigns/hunks")
local create_patch = gs_hunks.create_patch
local process_hunks = gs_hunks.process_hunks
local parse_diff_line = gs_hunks.parse_diff_line
local get_summary = gs_hunks.get_summary
local find_hunk = gs_hunks.find_hunk

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

local function dprint(...)
   if config.debug_mode then
      require('gitsigns/debug').dprint(...)
   end
end

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

local function path_exists(path)
   return uv.fs_stat(path) and true or false
end

local job_cnt = 0

local function run_job(job_spec)
   if config.debug_mode then
      local cmd = job_spec.command .. ' ' .. table.concat(job_spec.args, ' ')
      dprint('Running: ' .. cmd)
   end
   Job:new(job_spec):start()
   job_cnt = job_cnt + 1
end

local function git_relative(file, toplevel)
   return function(callback)
      local relpath
      local object_name
      local mode_bits
      run_job({
         command = 'git',
         args = {
            '--no-pager',
            'ls-files',
            '--stage',
            '--others',
            '--exclude-standard',
            file,
         },
         cwd = toplevel,
         on_stdout = function(_, line)
            local parts = vim.split(line, ' +')
            if #parts > 1 then
               mode_bits = parts[1]
               object_name = parts[2]
               relpath = vim.split(parts[3], '\t', true)[2]
            else
               relpath = parts[1]
            end
         end,
         on_exit = function(_, _)
            callback(relpath, object_name, mode_bits)
         end,
      })
   end
end

local get_staged_txt = function(toplevel, relpath)
   return function(callback)
      local content = {}
      run_job({
         command = 'git',
         args = { '--no-pager', 'show', ':' .. relpath },
         cwd = toplevel,
         on_stdout = function(_, line)
            table.insert(content, line)
         end,
         on_exit = function(_, code)
            callback(code == 0 and content or nil)
         end,
      })
   end
end

local run_diff = function(staged, text)
   return function(callback)
      local results = {}
      run_job({
         command = 'git',
         args = {
            '--no-pager',
            'diff',
            '--color=never',
            '--diff-algorithm=' .. config.diff_algorithm,
            '--patch-with-raw',
            '--unified=0',
            staged,
            '-',
         },
         writer = text,
         on_stdout = function(_, line)
            if vim.startswith(line, '@@') then
               table.insert(results, parse_diff_line(line))
            else
               if #results > 0 then
                  table.insert(results[#results].lines, line)
               end
            end
         end,
         on_stderr = function(_, line)
            print('error: ' .. line, 'NA', 'run_diff')
         end,
         on_exit = function()
            callback(results)
         end,
      })
   end
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

local function process_abbrev_head(gitdir, head_str)
   if not gitdir then
      return head_str
   end
   if head_str == 'HEAD' then
      if path_exists(gitdir .. '/rebase-merge') or
         path_exists(gitdir .. '/rebase-apply') then
         return '(rebasing)'
      elseif config.debug_mode then
         return head_str
      else
         return ''
      end
   end
   return head_str
end

local get_repo_info = function(path)
   return function(callback)
      local out = {}
      run_job({
         command = 'git',
         args = { 'rev-parse',
            '--show-toplevel',
            '--absolute-git-dir',
            '--abbrev-ref', 'HEAD',
         },
         cwd = path,
         on_stdout = function(_, line)
            table.insert(out, line)
         end,
         on_exit = vim.schedule_wrap(function()
            local toplevel = out[1]
            local gitdir = out[2]
            local abbrev_head = process_abbrev_head(gitdir, out[3])
            callback(toplevel, gitdir, abbrev_head)
         end),
      })
   end
end

local add_signs = function(bufnr, signs, reset)
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
   local staged_txt = await(get_staged_txt, toplevel, relpath)

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
   bcache.hunks = await(run_diff, bcache.staged, buftext)

   local status = get_summary(bcache.hunks)
   status.head = bcache.abbrev_head

   local signs = process_hunks(bcache.hunks)

   await_main()

   add_signs(bufnr, signs, true)

   Status:update(bufnr, status)

   update_cnt = update_cnt + 1
   dprint(string.format('updates: %s, jobs: %s', update_cnt, job_cnt), bufnr, 'update')
end)

local update_debounced = debounce_trailing(100, arun(update))

local watch_index = async(function(bufnr, gitdir, on_change)

   dprint('Watching index', bufnr, 'watch_index')

   local index = gitdir .. '/index'
   local w = uv.new_fs_poll()
   w:start(index, config.watch_index.interval, on_change)

   return w
end)

local stage_lines = function(toplevel, lines)
   return function(callback)
      local status = true
      local err = {}
      run_job({
         command = 'git',
         args = { 'apply', '--cached', '--unidiff-zero', '-' },
         cwd = toplevel,
         writer = lines,
         on_stderr = function(_, line)
            status = false
            table.insert(err, line)
         end,
         on_exit = function()
            if not status then
               local s = table.concat(err, '\n')
               error('Cannot stage lines. Command stderr:\n\n' .. s)
            end
            callback()
         end,
      })
   end
end

local add_file = function(toplevel, file)
   return function(callback)
      local status = true
      local err = {}
      run_job({
         command = 'git',
         args = { 'add', '--intent-to-add', file },
         cwd = toplevel,
         on_stderr = function(_, line)
            status = false
            table.insert(err, line)
         end,
         on_exit = function()
            if not status then
               local s = table.concat(err, '\n')
               error('Cannot add file. Command stderr:\n\n' .. s)
            end
            callback()
         end,
      })
   end
end

local add_to_index = async(function(bcache)
   local relpath, toplevel = bcache.relpath, bcache.toplevel

   await_main()
   await(add_file, toplevel, relpath)


   await_main()
   _, bcache.object_name, bcache.mode_bits = 
await(git_relative, relpath, toplevel)
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

   if not path_exists(bcache.file) then
      print("Error: Cannot stage lines. Please add the file to the working tree.")
      return
   end

   if not bcache.object_name then

      await(add_to_index, bcache)
   end

   local lines = create_patch(bcache.relpath, hunk, bcache.mode_bits)

   await_main()
   await(stage_lines, bcache.toplevel, lines)

   table.insert(bcache.staged_diffs, hunk)

   local signs = process_hunks({ hunk })

   await_main()






   for _, s in ipairs(signs) do
      vim.fn.sign_unplace('gitsigns_ns', { buffer = bufnr, id = s.lnum })
   end
end)

local reset_hunk = function()
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
   await(stage_lines, bcache.toplevel, lines)

   table.remove(bcache.staged_diffs)

   local signs = process_hunks({ hunk })

   await_main()
   add_signs(bufnr, signs)
end)

local NavHunkOpts = {}




local function nav_hunk(options)
   local forwards = options.forwards
   local bcache = get_cache_opt(current_buf())
   if not bcache then
      return
   end
   local hunks = bcache.hunks
   if not hunks or vim.tbl_isempty(hunks) then
      return
   end
   local line = api.nvim_win_get_cursor(0)[1]
   local row
   if forwards then
      for i = 1, #hunks do
         local hunk = hunks[i]
         if hunk.start > line then
            row = hunk.start
            break
         end
      end
   else
      for i = #hunks, 1, -1 do
         local hunk = hunks[i]
         if hunk.dend < line then
            row = hunk.start
            break
         end
      end
   end

   local wrap
   if options.wrap ~= nil then
      wrap = options.wrap
   else
      wrap = vim.o.wrapscan
   end
   if not row and wrap then
      row = math.max(hunks[forwards and 1 or #hunks].start, 1)
   end
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

local detach = function(bufnr)
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

local detach_all = function()
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

local attach = throttle_leading(100, sync(function()
   local cbuf = current_buf()
   if cache[cbuf] ~= nil then
      dprint('Already attached', cbuf, 'attach')
      return
   end
   dprint('Attaching', cbuf, 'attach')

   local file = get_buf_path(cbuf)

   for _, p in ipairs(vim.split(file, '/')) do
      if p == '.git' then
         dprint('In git dir', cbuf, 'attach')
         return
      end
   end

   local file_dir = dirname(file)

   if not file_dir or not path_exists(file_dir) then
      dprint('Not a path', cbuf, 'attach')
      return
   end

   local toplevel, gitdir, abbrev_head = 
await(get_repo_info, file_dir)

   if not gitdir then
      dprint('Not in git repo', cbuf, 'attach')
      return
   end

   Status:update_head(cbuf, abbrev_head)

   if not path_exists(file) or uv.fs_stat(file).type == 'directory' then
      dprint('Not a file', cbuf, 'attach')
      return
   end

   await_main()
   local relpath, object_name, mode_bits = 
await(git_relative, file, toplevel)

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
   }

   cache[cbuf].index_watcher = await(watch_index, cbuf, gitdir,
sync(function()
      dprint('Index update', cbuf, 'watcher_cb')
      local bcache = get_cache(cbuf)

      await_main()
      local _, _, abbrev_head0 = 
await(get_repo_info, file_dir)
      Status:update_head(cbuf, abbrev_head0)
      bcache.abbrev_head = abbrev_head0

      await_main()
      local _, object_name0, mode_bits0 = 
await(git_relative, file, toplevel)
      if object_name0 == bcache.object_name then
         dprint('File not changed', cbuf, 'watcher_cb')
         return
      end
      bcache.object_name = object_name0
      bcache.mode_bits = mode_bits0
      await(update, cbuf)
   end))



   await(update, cbuf)

   await_main()

   api.nvim_buf_attach(cbuf, false, {
      on_lines = function(_, buf)
         if not get_cache_opt(buf) then
            dprint('Cache for buffer ' .. buf .. ' was nil. Detaching', 'on_lines')
            return true
         end
         update_debounced(buf)
      end,
      on_detach = function(_, buf)
         detach(buf)
      end,
   })

   apply_keymaps(true)
end))


local function setup(cfg)
   config = process_config(cfg)



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

local function run_blame(file, toplevel, lines, lnum)
   return function(callback)
      local results = {}
      run_job({
         command = 'git',
         args = {
            '--no-pager',
            'blame',
            '--contents', '-',
            '-L', lnum .. ',+1',
            '--line-porcelain',
            file,
         },
         writer = lines,
         cwd = toplevel,
         on_stdout = function(_, line)
            table.insert(results, line)
         end,
         on_exit = function()
            local ret = {}
            local header = vim.split(table.remove(results, 1), ' ')
            ret.sha = header[1]
            ret.abbrev_sha = string.sub(ret.sha, 1, 8)
            ret.orig_lnum = header[2]
            ret.final_lnum = header[3]
            for _, l in ipairs(results) do
               if not vim.startswith(l, '\t') then
                  local cols = vim.split(l, ' ')
                  local key = table.remove(cols, 1)
                  ret[key] = table.concat(cols, ' ')
               end
            end
            callback(ret)
         end,
      })
   end
end

local blame_line = sync(function()
   local bufnr = current_buf()

   local bcache = get_cache_opt(bufnr)
   if not bcache then
      return
   end

   local buftext = api.nvim_buf_get_lines(bufnr, 0, -1, false)
   local lnum = api.nvim_win_get_cursor(0)[1]
   local result = await(run_blame, bcache.file, bcache.toplevel, buftext, lnum)

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
