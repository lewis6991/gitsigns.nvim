local a = require('plenary.async_lib.async')
local await      = a.await
local async_void = a.async_void
local scheduler  = a.scheduler

local Status        = require("gitsigns.status")
local cache         = require('gitsigns.cache').cache
local config        = require('gitsigns.config').config
local manager       = require('gitsigns.manager')
local mk_repeatable = require('gitsigns.repeat').mk_repeatable
local popup         = require('gitsigns.popup')
local signs         = require('gitsigns.signs')
local util          = require('gitsigns.util')

local gs_hunks = require('gitsigns.hunks')
local Hunk = gs_hunks.Hunk

local api = vim.api
local current_buf = api.nvim_get_current_buf

local record NavHunkOpts
  forwards: boolean
  wrap: boolean
end

local record M
  stage_hunk         : function -- function()
  undo_stage_hunk    : function -- function()
  reset_hunk         : function -- function(bufnr: integer, hunk: Hunk)

  stage_buffer       : function -- function()
  reset_buffer       : function -- function()
  reset_buffer_index : function -- function()

  next_hunk          : function(NavHunkOpts)
  prev_hunk          : function(NavHunkOpts)
  preview_hunk       : function()
  select_hunk        : function()

  blame_line         : function -- function()
  change_base        : function(base: string)
  diffthis           : function -- function(base: string)

  get_actions        : function(bufnr: integer, lnum: integer)
end

local function get_cursor_hunk(bufnr: integer, hunks: {Hunk}): Hunk
  bufnr = bufnr or current_buf()
  hunks = hunks or cache[bufnr].hunks

  local lnum = api.nvim_win_get_cursor(0)[1]
  return gs_hunks.find_hunk(lnum, hunks)
end

M.stage_hunk = mk_repeatable(async_void(function()
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

  await(bcache.git_obj:stage_hunks({hunk}))

  table.insert(bcache.staged_diffs, hunk)
  bcache.compare_text = nil -- Invalidate

  local hunk_signs = gs_hunks.process_hunks({hunk})

  await(scheduler())

  -- If watch_index is enabled then that will eventually kick in and update the
  -- signs, however for  smoother UX we can update the signs immediately without
  -- running a full diff.
  --
  -- We cannot update the status bar as that requires a full diff.
  for lnum, _ in pairs(hunk_signs) do
    signs.remove(bufnr, lnum)
  end
  await(manager.update(bufnr))
end))

M.reset_hunk = mk_repeatable(function(bufnr: integer, hunk: Hunk)
  bufnr = bufnr or current_buf()
  hunk = hunk or get_cursor_hunk(bufnr)
  if not hunk then
    return
  end

  local lstart, lend: integer, integer
  if hunk.type == 'delete' then
    lstart = hunk.start
    lend = hunk.start
  else
    local length = vim.tbl_count(vim.tbl_filter(function(l: string): boolean
      return vim.startswith(l, '+')
    end, hunk.lines))

    lstart = hunk.start - 1
    lend = hunk.start - 1 + length
  end
  api.nvim_buf_set_lines(bufnr, lstart, lend, false, gs_hunks.extract_removed(hunk))
end)

M.reset_buffer = function()
  local bufnr = current_buf()
  local bcache = cache[bufnr]
  if not bcache then
    return
  end

  api.nvim_buf_set_lines(bufnr, 0, -1, false, bcache:get_compare_text())
end

M.undo_stage_hunk = mk_repeatable(async_void(function()
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

  await(bcache.git_obj:stage_hunks({hunk}, true))
  bcache.compare_text = nil -- Invalidate
  await(scheduler())
  signs.add(config, bufnr, gs_hunks.process_hunks({hunk}))
end))

M.stage_buffer = async_void(function()
  local bufnr = current_buf()

  local bcache = cache[bufnr]
  if not bcache then
    return
  end

  -- Only process files with existing hunks
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
  bcache.compare_text = nil -- Invalidate

  await(scheduler())
  signs.remove(bufnr)
  Status:clear_diff(bufnr)
end)

M.reset_buffer_index = async_void(function()
  local bufnr = current_buf()
  local bcache = cache[bufnr]
  if not bcache then
    return
  end

  -- `bcache.staged_diffs` won't contain staged changes outside of current
  -- neovim session so signs added from this unstage won't be complete They will
  -- however be fixed by index watcher and properly updated We should implement
  -- some sort of initial population from git diff, after that this function can
  -- be improved to check if any staged hunks exists and it can undo changes
  -- using git apply line by line instead of reseting whole file
  local hunks = bcache.staged_diffs
  bcache.staged_diffs = {}

  await(bcache.git_obj:unstage_file())
  bcache.compare_text = nil -- Invalidate

  await(scheduler())
  signs.add(config, bufnr, gs_hunks.process_hunks(hunks))
end)

local function nav_hunk(options: NavHunkOpts)
  local bcache = cache[current_buf()]
  if not bcache then
    return
  end
  local hunks = bcache.hunks
  if not hunks or vim.tbl_isempty(hunks) then
    return
  end
  local line = api.nvim_win_get_cursor(0)[1]

  -- wrap around
  local wrap = vim.o.wrapscan
  if options.wrap ~= nil then
    wrap = options.wrap
  end

  local hunk = gs_hunks.find_nearest_hunk(line, hunks, options.forwards, wrap)

  if hunk == nil then
    return
  end

  local row = options.forwards and hunk.start or hunk.vend
  if row then
    -- Handle topdelete
    if row == 0 then
      row = 1
    end
    api.nvim_win_set_cursor(0, {row, 0})
  end
end

M.next_hunk = function(options: NavHunkOpts)
  options = options or {}
  options.forwards = true
  nav_hunk(options)
end

M.prev_hunk = function(options: NavHunkOpts)
  options = options or {}
  options.forwards = false
  nav_hunk(options)
end

local ns = api.nvim_create_namespace('gitsigns')

M.preview_hunk = function()
  local hunk = get_cursor_hunk()
  if not hunk then return end

  local _, bufnr = popup.create(hunk.lines, config.preview_config)
  api.nvim_buf_set_option(bufnr, 'filetype', 'diff')

  local regions = require('gitsigns.diff').run_word_diff(hunk.lines)
  for _, region in ipairs(regions) do
    local line, scol, ecol = region[1], region[3], region[4]
    api.nvim_buf_set_extmark(bufnr as integer, ns, line-1, scol, {
      end_col = ecol,
      hl_group = 'TermCursor'
    })
  end
end

M.select_hunk = function()
  local hunk = get_cursor_hunk()
  if not hunk then return end

  vim.cmd('normal! '..hunk.start..'GV'..hunk.vend..'G')
end

local function defer(duration: integer, callback: function()): vim.loop.Timer
  local timer = vim.loop.new_timer()
  timer:start(duration, 0, function()
    timer:stop()
    timer:close()
    vim.schedule_wrap(callback)()
  end)
  return timer
end

M.blame_line = async_void(function()
  local bufnr = current_buf()
  local bcache = cache[bufnr]
  if not bcache then return end

  local loading = defer(1000, function()
    popup.create({'Loading...'}, config.preview_config)
  end)

  await(scheduler())
  local buftext = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local lnum = api.nvim_win_get_cursor(0)[1]
  local result = await(bcache.git_obj:run_blame(buftext, lnum))
  pcall(function()
    loading:close()
  end)

  local date = os.date('%Y-%m-%d %H:%M', tonumber(result['author_time']))
  local lines = {
    ('%s %s (%s):'):format(result.abbrev_sha, result.author, date),
    result.summary
  }

  await(scheduler())

  local _, pbufnr = popup.create(lines, config.preview_config)

  local p1 = #result.abbrev_sha
  local p2 = #result.author
  local p3 = #date

  local function add_highlight(hlgroup: string, line: integer, start: integer, length: integer)
    api.nvim_buf_add_highlight(pbufnr, -1, hlgroup, line, start, start+length)
  end

  add_highlight('Directory', 0, 0      , p1)
  add_highlight('MoreMsg'  , 0, p1+1   , p2)
  add_highlight('Label'    , 0, p1+p2+2, p3+2)
end)

local function calc_base(base: string): string
  if base and base:sub(1, 1):match('[~\\^]') then
    base = 'HEAD'..base
  end
  return base
end

M.change_base = function(base: string)
  base = calc_base(base)
  local buf = current_buf()
  cache[buf].base = base
  cache[buf].compare_text = nil
end

M.diffthis = async_void(function(base: string)
  local bufnr = current_buf()
  local bcache = cache[bufnr]
  if not bcache then return end

  if api.nvim_win_get_option(0, 'diff') then return end

  local text: {string}
  local comp_obj = bcache:get_compare_obj(calc_base(base))
  if base then
    text = await(bcache.git_obj:get_show_text(comp_obj))
    await(scheduler())
  else
    text = bcache:get_compare_text()
  end

  local ft = api.nvim_buf_get_option(bufnr, 'filetype')

  local bufname = string.format('gitsigns://%s/%s', bcache.git_obj.gitdir, comp_obj)

  -- TDOD lewis6991 (27/05/21): Respect 'vertical' in diffopt
  vim.cmd("keepalt aboveleft vertical split "..bufname)

  local dbuf = current_buf()

  api.nvim_buf_set_option(dbuf, 'modifiable', true)
  api.nvim_buf_set_lines(dbuf, 0, -1, false, text)
  api.nvim_buf_set_option(dbuf, 'modifiable', false)

  api.nvim_buf_set_option(dbuf, 'filetype', ft)
  api.nvim_buf_set_option(dbuf, 'buftype', 'nowrite')

  vim.cmd(string.format('autocmd! WinClosed <buffer=%d> ++once call nvim_buf_delete(%d, {})', dbuf, dbuf))

  vim.cmd[[windo diffthis]]
end)

M.get_actions = function(): {string:function}
  local hunk = get_cursor_hunk()

  -- Do we want to return these(?):
  --    - stage_buffer
  --    - reset_buffer
  --    - reset_buffer_index
  --    - next_hunk
  --    - prev_hunk
  --    - change_base
  --    - diffthis

  local actions_l: {string} = {}
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
      'blame_line'
    }
  end

  local actions: {string:function} = {}
  for _, a in ipairs(actions_l) do
    actions[a] = (M as {string:function})[a]
  end

  return actions
end

return M
