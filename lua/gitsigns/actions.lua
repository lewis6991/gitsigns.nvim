local void = require('gitsigns.async').void
local scheduler = require('gitsigns.async').scheduler

local config = require('gitsigns.config').config
local mk_repeatable = require('gitsigns.repeat').mk_repeatable
local popup = require('gitsigns.popup')
local util = require('gitsigns.util')
local manager = require('gitsigns.manager')
local git = require('gitsigns.git')
local run_diff = require('gitsigns.diff')

local gs_cache = require('gitsigns.cache')
local cache = gs_cache.cache
local CacheEntry = gs_cache.CacheEntry

local gs_hunks = require('gitsigns.hunks')
local Hunk = gs_hunks.Hunk
local Hunk_Public = gs_hunks.Hunk_Public

local api = vim.api
local current_buf = api.nvim_get_current_buf



















local M = {QFListOpts = {}, }















































local C = {}









M.toggle_signs = function(value)
   if value ~= nil then
      config.signcolumn = value
   else
      config.signcolumn = not config.signcolumn
   end
   M.refresh()
   return config.signcolumn
end









M.toggle_numhl = function(value)
   if value ~= nil then
      config.numhl = value
   else
      config.numhl = not config.numhl
   end
   M.refresh()
   return config.numhl
end









M.toggle_linehl = function(value)
   if value ~= nil then
      config.linehl = value
   else
      config.linehl = not config.linehl
   end
   M.refresh()
   return config.linehl
end









M.toggle_word_diff = function(value)
   if value ~= nil then
      config.word_diff = value
   else
      config.word_diff = not config.word_diff
   end
   M.refresh()
   return config.word_diff
end









M.toggle_current_line_blame = function(value)
   if value ~= nil then
      config.current_line_blame = value
   else
      config.current_line_blame = not config.current_line_blame
   end
   M.refresh()
   return config.current_line_blame
end









M.toggle_deleted = function(value)
   if value ~= nil then
      config.show_deleted = value
   else
      config.show_deleted = not config.show_deleted
   end
   M.refresh()
   return config.show_deleted
end

local function get_cursor_hunk(bufnr, hunks)
   bufnr = bufnr or current_buf()
   hunks = hunks or cache[bufnr].hunks

   local lnum = api.nvim_win_get_cursor(0)[1]
   return gs_hunks.find_hunk(lnum, hunks)
end

local function update(bufnr)
   manager.update(bufnr)
   scheduler()
   if vim.wo.diff then
      require('gitsigns.diffthis').update(bufnr)
   end
end

local function get_range(params)
   local range
   if params.range > 0 then
      range = { params.line1, params.line2 }
   end
   return range
end















M.stage_hunk = mk_repeatable(void(function(range)
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

   bcache:invalidate()
   update(bufnr)
end))

C.stage_hunk = function(_pos_args, _named_args, params)
   M.stage_hunk(get_range(params))
end










M.reset_hunk = mk_repeatable(function(range)
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
      lstart = hunk.added.start
      lend = hunk.added.start
   else
      lstart = hunk.added.start - 1
      lend = hunk.added.start - 1 + hunk.added.count
   end
   util.set_lines(bufnr, lstart, lend, hunk.removed.lines)
end)

C.reset_hunk = function(_pos_args, _named_args, params)
   M.reset_hunk(get_range(params))
end


M.reset_buffer = function()
   local bufnr = current_buf()
   local bcache = cache[bufnr]
   if not bcache then
      return
   end

   util.set_lines(bufnr, 0, -1, bcache.compare_text)
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
   bcache:invalidate()
   update(bufnr)
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

   bcache:invalidate()
   update(bufnr)
end)







M.reset_buffer_index = void(function()
   local bufnr = current_buf()
   local bcache = cache[bufnr]
   if not bcache then
      return
   end







   bcache.staged_diffs = {}

   bcache.git_obj:unstage_file()

   bcache:invalidate()
   update(bufnr)
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


local function defer(fn)
   if vim.in_fast_event() then
      vim.schedule(fn)
   else
      vim.defer_fn(fn, 1)
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

   local row = opts.forwards and hunk.added.start or hunk.vend
   if row then

      if row == 0 then
         row = 1
      end
      vim.cmd([[ normal! m' ]])
      api.nvim_win_set_cursor(0, { row, 0 })
      if opts.foldopen then
         vim.cmd('silent! foldopen!')
      end
      if opts.preview or popup.is_open() then


         defer(M.preview_hunk)
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

local HlMark = popup.HlMark

local function lines_format(fmt,
   info)

   local ret = vim.deepcopy(fmt)

   for _, line in ipairs(ret) do
      for _, s in ipairs(line) do
         s[1] = util.expand_format(s[1], info)
      end
   end

   return ret
end

local function hlmarks_for_hunk(hunk, hl)
   local hls = {}

   local removed, added = hunk.removed, hunk.added

   if hl then
      hls[#hls + 1] = {
         hl_group = hl,
         start_row = 0,
         end_row = removed.count + added.count,
      }
   end

   hls[#hls + 1] = {
      hl_group = 'GitSignsDeletePreview',
      start_row = 0,
      end_row = removed.count,
   }

   hls[#hls + 1] = {
      hl_group = 'GitSignsAddPreview',
      start_row = removed.count,
      end_row = removed.count + added.count,
   }

   if config.diff_opts.internal then
      local removed_regions, added_regions = 
      require('gitsigns.diff_int').run_word_diff(removed.lines, added.lines)
      for _, region in ipairs(removed_regions) do
         hls[#hls + 1] = {
            hl_group = 'GitSignsDeleteInline',
            start_row = region[1] - 1,
            start_col = region[3],
            end_col = region[4],
         }
      end
      for _, region in ipairs(added_regions) do
         hls[#hls + 1] = {
            hl_group = 'GitSignsAddInline',
            start_row = region[1] - 1,
            start_col = region[3],
            end_col = region[4],
         }
      end
   end

   return hls
end

local function insert_hunk_hlmarks(fmt, hunk)
   for _, line in ipairs(fmt) do
      for _, s in ipairs(line) do
         local hl = s[2]
         if s[1] == '<hunk>' and type(hl) == "string" then
            s[2] = hlmarks_for_hunk(hunk, hl)
         end
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



M.preview_hunk = noautocmd(function()

   local bufnr = current_buf()
   local bcache = cache[bufnr]
   if not bcache then
      return
   end

   local hunk, index = get_cursor_hunk(bufnr, bcache.hunks)

   if not hunk then return end

   local lines_fmt = {
      { { 'Hunk <hunk_no> of <num_hunks>', 'Title' } },
      { { '<hunk>', 'NormalFloat' } },
   }

   insert_hunk_hlmarks(lines_fmt, hunk)

   local lines_spec = lines_format(lines_fmt, {
      hunk_no = index,
      num_hunks = #bcache.hunks,
      hunk = gs_hunks.patch_lines(hunk, vim.bo[bufnr].fileformat),
   })

   popup.create(lines_spec, config.preview_config)
end)


M.select_hunk = function()
   local hunk = get_cursor_hunk()
   if not hunk then return end

   vim.cmd('normal! ' .. hunk.added.start .. 'GV' .. hunk.vend .. 'G')
end





















M.get_hunks = function(bufnr)
   bufnr = bufnr or current_buf()
   if not cache[bufnr] then return end
   local ret = {}
   for _, h in ipairs(cache[bufnr].hunks or {}) do
      ret[#ret + 1] = {
         head = h.head,
         lines = gs_hunks.patch_lines(h, vim.bo[bufnr].fileformat),
         type = h.type,
         added = h.added,
         removed = h.removed,
      }
   end
   return ret
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

local function create_blame_fmt(is_committed, full)
   if not is_committed then
      return {
         { { '<author>', 'Label' } },
      }
   end

   local header = {
      { '<abbrev_sha> ', 'Directory' },
      { '<author> ', 'MoreMsg' },
      { '(<author_time:%Y-%m-%d %H:%M>)', 'Label' },
      { ':', 'NormalFloat' },
   }

   if full then
      return {
         header,
         { { '<body>', 'NormalFloat' } },
         { { 'Hunk <hunk_no> of <num_hunks>', 'Title' }, { ' <hunk_head>', 'LineNr' } },
         { { '<hunk>', 'NormalFloat' } },
      }
   end

   return {
      header,
      { { '<summary>', 'NormalFloat' } },
   }
end














M.blame_line = void(function(opts)
   opts = opts or {}

   local bufnr = current_buf()
   local bcache = cache[bufnr]
   if not bcache then return end

   local loading = vim.defer_fn(function()
      popup.create({ { { 'Loading...', 'Title' } } }, config.preview_config)
   end, 1000)

   scheduler()
   local buftext = util.buf_lines(bufnr)
   local fileformat = vim.bo[bufnr].fileformat
   local lnum = api.nvim_win_get_cursor(0)[1]
   local result = bcache.git_obj:run_blame(buftext, lnum, opts.ignore_whitespace)
   pcall(function()
      loading:close()
   end)

   local is_committed = result.sha and tonumber('0x' .. result.sha) ~= 0

   local blame_fmt = create_blame_fmt(is_committed, opts.full)

   local info = result

   if is_committed and opts.full then
      info.body = bcache.git_obj:command({ 'show', '-s', '--format=%B', result.sha })

      local hunk

      hunk, info.hunk_no, info.num_hunks = get_blame_hunk(bcache.git_obj.repo, result)

      info.hunk = gs_hunks.patch_lines(hunk, fileformat)
      info.hunk_head = hunk.head
      insert_hunk_hlmarks(blame_fmt, hunk)
   end

   scheduler()

   popup.create(lines_format(blame_fmt, info), config.preview_config)
end)

local function update_buf_base(buf, bcache, base)
   bcache.base = base
   bcache:invalidate()
   update(buf)
end


































M.change_base = void(function(base, global)
   base = util.calc_base(base)

   if global then
      config.base = base

      for bufnr, bcache in pairs(cache) do
         update_buf_base(bufnr, bcache, base)
      end
   else
      local bufnr = current_buf()
      local bcache = cache[bufnr]
      if not bcache then return end

      update_buf_base(bufnr, bcache, base)
   end
end)





M.reset_base = function(global)
   M.change_base(nil, global)
end

































M.diffthis = function(base, opts)
   opts = opts or {}
   local diffthis = require('gitsigns.diffthis')
   if not opts.vertical then
      opts.vertical = config.diff_opts.vertical
   end
   diffthis.diffthis(base, opts)
end

C.diffthis = function(pos_args, named_args, params)
   local opts = {
      vertical = named_args.vertical,
      split = named_args.split,
   }

   if params.smods then
      if params.smods.split ~= '' and opts.split == nil then
         opts.split = params.smods.split
      end
      if opts.vertical == nil then
         opts.vertical = params.smods.vertical
      end
   end

   M.diffthis(pos_args[1], opts)
end


























M.show = function(revision)
   local diffthis = require('gitsigns.diffthis')
   diffthis.show(revision)
end

local function hunks_to_qflist(buf_or_filename, hunks, qflist)
   for i, hunk in ipairs(hunks) do
      qflist[#qflist + 1] = {
         bufnr = type(buf_or_filename) == "number" and (buf_or_filename) or nil,
         filename = type(buf_or_filename) == "string" and buf_or_filename or nil,
         lnum = hunk.added.start,
         text = string.format('Lines %d-%d (%d/%d)',
         hunk.added.start, hunk.vend, i, #hunks),
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

      local repo = git.Repo.new(vim.loop.cwd())
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
   manager.reset_signs()
   require('gitsigns.highlight').setup_highlights()
   require('gitsigns.current_line_blame').setup()
   for k, v in pairs(cache) do
      v:invalidate()
      manager.update(k, v)
   end
end)

function M.get_cmd_func(name)
   return C[name]
end

return M
