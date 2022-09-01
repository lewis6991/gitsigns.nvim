local void = require('gitsigns.async').void
local awrap = require('gitsigns.async').wrap
local scheduler = require('gitsigns.async').scheduler

local gs_cache   = require('gitsigns.cache')
local CacheEntry = gs_cache.CacheEntry
local cache      = gs_cache.cache

local Signs             = require('gitsigns.signs')

local Status            = require("gitsigns.status")

local debounce_trailing = require('gitsigns.debounce').debounce_trailing
local throttle_by_id    = require('gitsigns.debounce').throttle_by_id
local gs_debug          = require("gitsigns.debug")
local dprint            = gs_debug.dprint
local dprintf           = gs_debug.dprintf
local eprint            = gs_debug.eprint
local subprocess        = require('gitsigns.subprocess')
local util              = require('gitsigns.util')
local run_diff          = require('gitsigns.diff')
local git               = require('gitsigns.git')
local uv                = require('gitsigns.uv')

local gs_hunks          = require("gitsigns.hunks")
local Hunk              = gs_hunks.Hunk

local config            = require('gitsigns.config').config

local api = vim.api

local signs: Signs

local record M
  update           : function(bufnr: integer, CacheEntry)
  update_debounced : function(bufnr: integer, CacheEntry)
  on_lines         : function(buf: integer, first: integer, last_orig: integer, last_new: integer): boolean
  watch_gitdir     : function(bufnr: integer, gitdir: string): vim.loop.FSPollObj
  update_cwd_head  : function()
  detach           : function(bufnr: integer, keep_signs: boolean)
  reset_signs      : function()
  setup            : function()
end

local schedule_if_buf_valid = function(buf: integer, cb: function)
  vim.schedule(function()
    if vim.api.nvim_buf_is_valid(buf) then
      cb()
    end
  end)
end

local scheduler_if_buf_valid = awrap(schedule_if_buf_valid, 2)

local function apply_win_signs(bufnr: integer, hunks: {Hunk}, top: integer, bot: integer, clear: boolean)
  if clear then
    signs:remove(bufnr)  -- Remove all signs
  end

  -- To stop the sign column width changing too much, if there are signs to be
  -- added but none of them are visible in the window, then make sure to add at
  -- least one sign. Only do this on the first call after an update when we all
  -- the signs have been cleared.
  if clear and hunks[1] then
    signs:add(bufnr, gs_hunks.calc_signs(hunks[1], hunks[1].added.start, hunks[1].added.start))
  end

  for _, hunk in ipairs(hunks or {}) do
    if top <= hunk.vend and bot >= hunk.added.start then
      signs:add(bufnr, gs_hunks.calc_signs(hunk, top, bot))
    end
    if hunk.added.start > bot then
      break
    end
  end
end

M.on_lines = function(buf: integer, first: integer, last_orig: integer, last_new: integer): boolean
  local bcache = cache[buf]
  if not bcache then
    dprint('Cache for buffer was nil. Detaching')
    return true
  end

  signs:on_lines(buf, first, last_orig, last_new)

  -- Signs in changed regions get invalidated so we need to force a redraw if
  -- any signs get removed.
  if signs:contains(buf, first, last_new) then
    -- Force a sign redraw on the next update (fixes #521)
    bcache.force_next_update = true
  end

  M.update_debounced(buf, cache[buf])
end

local ns = api.nvim_create_namespace('gitsigns')

local function apply_word_diff(bufnr: integer, row: integer)
  -- Don't run on folded lines
  if vim.fn.foldclosed(row+1) ~= -1 then
    return
  end

  if not cache[bufnr] or not cache[bufnr].hunks then
    return
  end

  local line = api.nvim_buf_get_lines(bufnr, row, row+1, false)[1]
  if not line then
    -- Invalid line
    return
  end

  local lnum = row + 1

  local hunk = gs_hunks.find_hunk(lnum, cache[bufnr].hunks)
  if not hunk then
    -- No hunk at line
    return
  end

  if hunk.added.count ~= hunk.removed.count then
    -- Only word diff if added count == removed
    return
  end

  local pos = lnum - hunk.added.start + 1

  local added_line = hunk.added.lines[pos]
  local removed_line = hunk.removed.lines[pos]

  local _, added_regions = require('gitsigns.diff_int').run_word_diff({removed_line}, {added_line})

  local cols = #line

  for _, region in ipairs(added_regions) do
    local rtype, scol, ecol = region[2], region[3], region[4]
    if scol <= cols then
      if ecol > cols then
        ecol = cols
      elseif ecol == scol then
        -- Make sure region is at least 1 column width
        ecol = scol + 1
      end
      api.nvim_buf_set_extmark(bufnr, ns, row, scol-1, {
        end_col = ecol-1,
        hl_group = rtype == 'add'    and 'GitSignsAddLnInline'
                or rtype == 'change' and 'GitSignsChangeLnInline'
                or                       'GitSignsDeleteLnInline',
        ephemeral = true,
        priority = 1000
      })
      api.nvim__buf_redraw_range(bufnr, row, row+1)
    end
  end
end

local ns_rm = api.nvim_create_namespace('gitsigns_removed')

local VIRT_LINE_LEN = 300

local function clear_deleted(bufnr: integer)
  local marks = api.nvim_buf_get_extmarks(bufnr, ns_rm, 0, -1, {})
  for _, mark in ipairs(marks as {{integer, integer, integer}}) do
    api.nvim_buf_del_extmark(bufnr, ns_rm, mark[1])
  end
end

local function show_deleted(bufnr: integer)
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
          {hunk.removed.lines[i]}, {hunk.added.lines[i]})

        for _, region in ipairs(regions) do
          local rline, scol, ecol = region[1], region[3], region[4]
          if rline > 1 then
            break
          end
          vline[#vline+1] = { line:sub(last_ecol, scol-1), 'GitSignsDeleteVirtLn'}
          vline[#vline+1] = { line:sub(scol, ecol-1), 'GitSignsDeleteVirtLnInline'}
          last_ecol = ecol
        end
      end

      if #line > 0 then
        vline[#vline+1] = { line:sub(last_ecol, -1), 'GitSignsDeleteVirtLn'}
      end

      -- Add extra padding so the entire line is highlighted
      local padding = string.rep(' ', VIRT_LINE_LEN-#line)
      vline[#vline+1] = { padding, 'GitSignsDeleteVirtLn'}

      virt_lines[i] = vline
    end

    local topdelete = hunk.added.start == 0 and hunk.type == 'delete'

    local row = topdelete and 0 or hunk.added.start - 1
    api.nvim_buf_set_extmark(bufnr, ns_rm, row, -1, {
      virt_lines       = virt_lines,
      -- TODO(lewis6991): Note virt_lines_above doesn't work on row 0 neovim/neovim#16166
      virt_lines_above = hunk.type ~= 'delete' or topdelete,
    })
  end
end

local update_cnt = 0

-- Ensure updates cannot be interleaved.
-- Since updates are asynchronous we need to make sure an update isn't performed
-- whilst another one is in progress. If this happens then schedule another
-- update after the current one has completed.
M.update = throttle_by_id(function(bufnr: integer, bcache: CacheEntry)
  local __FUNC__ = 'update'
  bcache = bcache or cache[bufnr]
  if not bcache then
    eprint('Cache for buffer '..bufnr..' was nil')
    return
  end

  scheduler_if_buf_valid(bufnr)
  local buftext = util.buf_lines(bufnr)
  local git_obj = bcache.git_obj

  if not bcache.compare_text or config._refresh_staged_on_update then
    bcache.compare_text = git_obj:get_show_text(bcache:get_compare_rev())
  end

  local old_hunks = bcache.hunks
  bcache.hunks = run_diff(bcache.compare_text, buftext)

  scheduler_if_buf_valid(bufnr)
  -- Note the decoration provider may have invalidated bcache.hunks at this
  -- point
  if bcache.force_next_update or gs_hunks.compare_heads(bcache.hunks, old_hunks) then
    -- Apply signs to the window. Other signs will be added by the decoration
    -- provider as they are drawn.
    apply_win_signs(bufnr, bcache.hunks, vim.fn.line('w0'), vim.fn.line('w$'), true)

    show_deleted(bufnr)
    bcache.force_next_update = false
  end
  local summary = gs_hunks.get_summary(bcache.hunks)
  summary.head = git_obj.repo.abbrev_head
  Status:update(bufnr, summary)

  update_cnt = update_cnt + 1

  dprintf('updates: %s, jobs: %s', update_cnt, subprocess.job_cnt)
end, true)

M.detach = function(bufnr: integer, keep_signs: boolean)
  if not keep_signs then
    signs:remove(bufnr)  -- Remove all signs
  end
end

local function handle_moved(bufnr: integer, bcache: CacheEntry, old_relpath: string)
  local git_obj = bcache.git_obj
  local do_update = false

  local new_name = git_obj:has_moved()
  if new_name then
    dprintf('File moved to %s', new_name)
    git_obj.relpath = new_name
    if not git_obj.orig_relpath then
      git_obj.orig_relpath = old_relpath
    end
    do_update = true
  elseif git_obj.orig_relpath then
    local orig_file = git_obj.repo.toplevel..util.path_sep..git_obj.orig_relpath
    if git_obj:file_info(orig_file).relpath then
      dprintf('Moved file reset')
      git_obj.relpath = git_obj.orig_relpath
      git_obj.orig_relpath = nil
      do_update = true
    end
  else
    -- File removed from index, do nothing
  end

  if do_update then
    git_obj.file = git_obj.repo.toplevel..util.path_sep..git_obj.relpath
    bcache.file = git_obj.file
    git_obj:update_file_info()
    scheduler()
    api.nvim_buf_set_name(bufnr, bcache.file)
  end
end


M.watch_gitdir = function(bufnr: integer, gitdir: string): vim.loop.FSPollObj
  if not config.watch_gitdir.enable then
    return
  end

  dprintf('Watching git dir')
  local w = uv.new_fs_poll(true) as vim.loop.FSPollObj
  w:start(gitdir, config.watch_gitdir.interval, void(function(err: string)
    local __FUNC__ = 'watcher_cb'
    if err then
      dprintf('Git dir update error: %s', err)
      return
    end
    dprint('Git dir update')

    local bcache = cache[bufnr]

    if not bcache then
      -- Very occasionally an external git operation may cause the buffer to
      -- detach and update the git dir simultaneously. When this happens this
      -- handler will trigger but there will be no cache.
      dprint('Has detached, aborting')
      return
    end

    local git_obj = bcache.git_obj

    git_obj.repo:update_abbrev_head()

    scheduler()
    Status:update(bufnr, { head = git_obj.repo.abbrev_head})

    local was_tracked = git_obj.object_name ~= nil
    local old_relpath = git_obj.relpath

    if not git_obj:update_file_info() then
      dprint('File not changed')
      return
    end

    if config.watch_gitdir.follow_files and was_tracked and not git_obj.object_name then
      -- File was tracked but is no longer tracked. Must of been removed or
      -- moved. Check if it was moved and switch to it.
      handle_moved(bufnr, bcache, old_relpath)
    end

    -- Invalidate
    bcache.compare_text = nil

    M.update(bufnr, bcache)
  end))
  return w
end

local cwd_watcher: vim.loop.FSPollObj

local function update_cwd_head_var(head: string)
  if head then
    api.nvim_set_var('gitsigns_head', head)
  else
    pcall(api.nvim_del_var, 'gitsigns_head')
  end
end

M.update_cwd_head = void(function()
  if cwd_watcher then
    cwd_watcher:stop()
  else
    cwd_watcher = uv.new_fs_poll(true) as vim.loop.FSPollObj
  end

  local cwd = vim.loop.cwd()
  local gitdir, head: string, string

  -- Look in the cache first
  for _, bcache in pairs(cache as {number:CacheEntry}) do
    local repo = bcache.git_obj.repo
    if repo.toplevel == cwd then
      head = repo.abbrev_head
      gitdir = repo.gitdir
      break
    end
  end

  if not head or not gitdir then
    local info = git.get_repo_info(cwd)
    gitdir = info.gitdir
    head = info.abbrev_head
  end

  scheduler()
  update_cwd_head_var(head)

  if not gitdir then
    return
  end

  local towatch = gitdir..'/HEAD'

  if cwd_watcher:getpath() == towatch then
    -- Already watching
    return
  end

  -- Watch .git/HEAD to detect branch changes
  cwd_watcher:start(
    towatch,
    config.watch_gitdir.interval,
    void(function(err: string)
      local __FUNC__ = 'cwd_watcher_cb'
      if err then
        dprintf('Git dir update error: %s', err)
        return
      end
      dprint('Git cwd dir update')

      local new_head = git.get_repo_info(cwd).abbrev_head
      scheduler()
      update_cwd_head_var(new_head)
    end)
  )
end)

M.reset_signs = function()
  signs:reset()  -- Remove all signs
end

M.setup = function()
  -- Calling this before any await calls will stop nvim's intro messages being
  -- displayed
  api.nvim_set_decoration_provider(ns, {
    on_win = function(_, _, bufnr: integer, topline: integer, botline_guess: integer): boolean
      local bcache = cache[bufnr]
      if not bcache or not bcache.hunks then
        return false
      end
      local botline = math.min(botline_guess, api.nvim_buf_line_count(bufnr))
      apply_win_signs(bufnr, bcache.hunks, topline+1, botline+1)

      if not (config.word_diff and config.diff_opts.internal) then
        return false
      end
    end,
    on_line = function(_, _winid: integer, bufnr: integer, row: integer)
      apply_word_diff(bufnr, row)
    end
  })

  signs = Signs.new(config.signs)
  M.update_debounced = debounce_trailing(config.update_debounce, void(M.update))
end

return M
