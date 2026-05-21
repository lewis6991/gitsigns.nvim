local async = require('gitsigns.async')
local log = require('gitsigns.debug.log')
local util = require('gitsigns.util')
local run_diff = require('gitsigns.diff')
local Hunks = require('gitsigns.hunks')

local debounce_trailing = require('gitsigns.debounce').debounce_trailing
local throttle_async = require('gitsigns.debounce').throttle_async

local cache = require('gitsigns.cache').cache
local Config = require('gitsigns.config')
local config = Config.config

local api = vim.api

--- @class gitsigns.manager
local M = {}

--- @class (exact) Gitsigns.ManagerUpdate
--- @field bufnr                integer
--- @field bcache               Gitsigns.CacheEntry
--- @field hunks_changed        boolean
--- @field hunks_staged_changed boolean

--- @class (exact) Gitsigns.ManagerLines
--- @field bufnr     integer
--- @field bcache    Gitsigns.CacheEntry
--- @field first     integer
--- @field last_orig integer
--- @field last_new  integer

--- @class (exact) Gitsigns.ManagerWin
--- @field ns      integer
--- @field winid   integer
--- @field bufnr   integer
--- @field topline integer
--- @field botline integer
--- @field bcache? Gitsigns.CacheEntry

--- @class (exact) Gitsigns.ManagerLine
--- @field ns      integer
--- @field winid   integer
--- @field bufnr   integer
--- @field row     integer
--- @field bcache? Gitsigns.CacheEntry

--- @alias Gitsigns.ManagerUpdateCb fun(ctx: Gitsigns.ManagerUpdate)
--- @alias Gitsigns.ManagerLinesCb fun(ctx: Gitsigns.ManagerLines)
--- @alias Gitsigns.ManagerDetachCb fun(bufnr: integer, keep_signs?: boolean)
--- Return true to request on_line callbacks for the window.
--- @alias Gitsigns.ManagerWinCb fun(ctx: Gitsigns.ManagerWin): boolean?
--- @alias Gitsigns.ManagerLineCb fun(ctx: Gitsigns.ManagerLine)

--- @type Gitsigns.ManagerUpdateCb[]
local update_callbacks = {}

--- @type Gitsigns.ManagerLinesCb[]
local lines_callbacks = {}

--- @type Gitsigns.ManagerDetachCb[]
local detach_callbacks = {}

--- @type Gitsigns.ManagerWinCb[]
local win_callbacks = {}

--- @type Gitsigns.ManagerLineCb[]
local line_callbacks = {}

--- @param cb Gitsigns.ManagerUpdateCb
function M.on_update(cb)
  update_callbacks[#update_callbacks + 1] = cb
end

--- @param cb Gitsigns.ManagerLinesCb
function M.on_lines(cb)
  lines_callbacks[#lines_callbacks + 1] = cb
end

--- @param cb Gitsigns.ManagerDetachCb
function M.on_detach(cb)
  detach_callbacks[#detach_callbacks + 1] = cb
end

--- @param cb Gitsigns.ManagerWinCb
function M.on_win(cb)
  win_callbacks[#win_callbacks + 1] = cb
end

--- @param cb Gitsigns.ManagerLineCb
function M.on_line(cb)
  line_callbacks[#line_callbacks + 1] = cb
end

--- @param buf integer
--- @param first integer
--- @param last_orig integer
--- @param last_new integer
--- @return true?
function M.handle_on_lines(buf, first, last_orig, last_new)
  local bcache = cache[buf]
  if not bcache then
    log.dprint('Cache for buffer was nil. Detaching')
    return true
  end

  bcache:on_lines(first, last_orig, last_new)

  for _, cb in ipairs(lines_callbacks) do
    cb({
      bufnr = buf,
      bcache = bcache,
      first = first,
      last_orig = last_orig,
      last_new = last_new,
    })
  end

  M.update_sync_debounced(buf)
end

local ns = api.nvim_create_namespace('gitsigns')

--- @param bufnr integer
--- @return boolean
local function buf_in_view(bufnr)
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    if api.nvim_win_get_buf(win) == bufnr then
      return true
    end
  end
  return false
end

--- @async
--- @param bcache Gitsigns.CacheEntry
--- @param fn async fun()
local function update_lock(bcache, fn)
  if not config._update_lock then
    fn()
  else
    bcache.git_obj:lock(fn)
  end
end

--- @async
--- Ensure updates cannot be interleaved.
--- Since updates are asynchronous we need to make sure an update isn't performed
--- whilst another one is in progress. If this happens then schedule another
--- update after the current one has completed.
--- @param bufnr integer
M.update = throttle_async({ hash = 1, schedule = true }, function(bufnr)
  local bcache = cache[bufnr]
  if not bcache or not bcache:schedule() then
    return
  end

  if not buf_in_view(bufnr) then
    log.dprint('Buffer not in view, deferring update')
    bcache.update_on_view = true
    return
  end
  bcache.update_on_view = nil

  update_lock(bcache, function()
    local old_hunks, old_hunks_staged = bcache.hunks, bcache.hunks_staged
    bcache.hunks, bcache.hunks_staged = nil, nil

    local git_obj = bcache.git_obj
    local file_mode = bcache.file_mode

    if not bcache.compare_text or config._refresh_staged_on_update or file_mode then
      if file_mode then
        bcache.compare_text = util.file_lines(git_obj.file)
      else
        bcache.compare_text = git_obj:get_show_text()
      end
      if not bcache:schedule(true) then
        return
      end
    end

    local buftext = util.buf_lines(bufnr)

    bcache.hunks = run_diff(bcache.compare_text, buftext)
    if not bcache:schedule() then
      return
    end

    local bufname = api.nvim_buf_get_name(bufnr)
    local rev_is_index = not git_obj:from_tree()

    if
      config.signs_staged_enable
      and not file_mode
      and (rev_is_index or bufname:match('^fugitive://') or bufname:match('^gitsigns://'))
    then
      if not bcache.compare_text_head or config._refresh_staged_on_update then
        -- When the revision is from the index, we compare against HEAD to
        -- show the staged changes.
        --
        -- When showing a revision buffer (a buffer that represents the revision
        -- of a specific file and does not have a corresponding file on disk), we
        -- utilize the staged signs to represent the changes introduced in that
        -- revision. Therefore we compare against the previous commit. Note there
        -- should not be any normal signs for these buffers.
        local staged_rev = rev_is_index and 'HEAD' or git_obj.revision .. '^'
        bcache.compare_text_head = git_obj:get_show_text(staged_rev)
        if not bcache:schedule(true) then
          return
        end
      end
      local hunks_head = run_diff(bcache.compare_text_head, buftext)
      if not bcache:schedule() then
        return
      end
      bcache.hunks_staged = Hunks.filter_common(hunks_head, bcache.hunks)
    end

    -- Note the decoration provider may have invalidated bcache.hunks at this
    -- point
    local hunks_changed = bcache.force_next_update or Hunks.compare_heads(bcache.hunks, old_hunks)
    local hunks_staged_changed = Hunks.compare_heads(bcache.hunks_staged, old_hunks_staged)

    if hunks_changed or hunks_staged_changed then
      bcache.force_next_update = false

      for _, cb in ipairs(update_callbacks) do
        cb({
          bufnr = bufnr,
          bcache = bcache,
          hunks_changed = hunks_changed,
          hunks_staged_changed = hunks_staged_changed,
        })
      end
    end
  end)
end)

M.update_sync_debounced = debounce_trailing({
  timeout = function()
    return config.update_debounce
  end,
  hash = 1,
}, function(bufnr)
  async.run(M.update, bufnr):raise_on_error()
end)

--- @param bufnr integer
--- @param keep_signs? boolean
function M.detach(bufnr, keep_signs)
  for _, cb in ipairs(detach_callbacks) do
    cb(bufnr, keep_signs)
  end
end

--- @param _ 'win'
--- @param winid integer
--- @param bufnr integer
--- @param topline integer
--- @param botline_guess integer
--- @return boolean
local function on_win(_, winid, bufnr, topline, botline_guess)
  local bcache = cache[bufnr]
  local botline = math.min(botline_guess, api.nvim_buf_line_count(bufnr))

  local wants_on_line = false

  local ctx = {
    ns = ns,
    winid = winid,
    bufnr = bufnr,
    topline = topline,
    botline = botline,
    bcache = bcache,
  }
  for _, cb in ipairs(win_callbacks) do
    wants_on_line = cb(ctx) or wants_on_line
  end

  return wants_on_line
end

--- @param _ 'line'
--- @param winid integer
--- @param bufnr integer
--- @param row integer
local function on_line(_, winid, bufnr, row)
  local ctx = {
    ns = ns,
    winid = winid,
    bufnr = bufnr,
    row = row,
    bcache = cache[bufnr],
  }
  for _, cb in ipairs(line_callbacks) do
    cb(ctx)
  end
end

M.setup = util.once(function()
  -- Load default runtime subscribers here, not at module load, so requiring
  -- manager stays cheap.
  require('gitsigns.sign_renderer')
  require('gitsigns.status')
  require('gitsigns.deleted_preview')
  require('gitsigns.word_diff')

  api.nvim_create_augroup('gitsigns', { clear = false })

  -- Calling this before any await calls will stop nvim's intro messages being
  -- displayed
  api.nvim_set_decoration_provider(ns, {
    on_win = on_win,
    on_line = on_line,
  })

  -- These options change render output derived from cached hunks.
  Config.subscribe({ 'signcolumn', 'numhl', 'linehl', 'show_deleted', 'word_diff' }, function()
    for k, v in pairs(cache) do
      v:invalidate(true)
      M.update_sync_debounced(k)
    end
  end)

  api.nvim_create_autocmd('OptionSet', {
    group = 'gitsigns',
    pattern = { 'fileformat', 'bomb', 'eol' },
    callback = function(args)
      local buf = args.buf
      local bcache = cache[buf]
      if not bcache then
        return
      end
      bcache:invalidate(true)
      M.update_sync_debounced(buf)
    end,
  })

  do -- deferred updates from file watcher
    api.nvim_create_autocmd('TabEnter', {
      group = 'gitsigns',
      desc = 'Gitsigns: deferred updates',
      callback = function()
        for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
          local bufnr = api.nvim_win_get_buf(win)
          if cache[bufnr] and cache[bufnr].update_on_view then
            log.dprint('TabEnter update')
            async.run(M.update, bufnr):raise_on_error()
          end
        end
      end,
    })

    api.nvim_create_autocmd('BufEnter', {
      group = 'gitsigns',
      desc = 'Gitsigns: deferred updates',
      callback = function(args)
        local bufnr = args.buf
        if cache[bufnr] and cache[bufnr].update_on_view then
          log.dprint('BufEnter update')
          async.run(M.update, bufnr):raise_on_error()
        end
      end,
    })
  end

  require('gitsigns.current_line_blame')
end)

return M
