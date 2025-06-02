local async = require('gitsigns.async')
local log = require('gitsigns.debug.log')
local util = require('gitsigns.util')
local run_diff = require('gitsigns.diff')
local Hunks = require('gitsigns.hunks')
local Signs = require('gitsigns.signs')
local Status = require('gitsigns.status')

local debounce_trailing = require('gitsigns.debounce').debounce_trailing
local throttle_by_id = require('gitsigns.debounce').throttle_by_id

local cache = require('gitsigns.cache').cache
local Config = require('gitsigns.config')
local config = Config.config

local api = vim.api

local signs_normal = Signs.new()
local signs_staged = Signs.new(true)

--- @class gitsigns.manager
local M = {}

--- @param bufnr integer
--- @param signs Gitsigns.Signs
--- @param hunks? Gitsigns.Hunk.Hunk[]
--- @param top integer
--- @param bot integer
--- @param clear? boolean
--- @param untracked boolean
--- @param filter? fun(line: integer):boolean
local function apply_win_signs0(bufnr, signs, hunks, top, bot, clear, untracked, filter)
  if clear then
    signs:remove(bufnr) -- Remove all signs
  end

  hunks = hunks or {}

  for i, hunk in ipairs(hunks) do
    --- @type Gitsigns.Hunk.Hunk?, Gitsigns.Hunk.Hunk?
    local prev_hunk, next_hunk = hunks[i - 1], hunks[i + 1]

    -- To stop the sign column width changing too much, if there are signs to be
    -- added but none of them are visible in the window, then make sure to add at
    -- least one sign. Only do this on the first call after an update when we all
    -- the signs have been cleared.
    if clear and i == 1 then
      signs:add(
        bufnr,
        Hunks.calc_signs(prev_hunk, hunk, next_hunk, hunk.added.start, hunk.added.start, untracked),
        filter
      )
    end

    signs:add(bufnr, Hunks.calc_signs(prev_hunk, hunk, next_hunk, top, bot, untracked), filter)
    if hunk.added.start > bot then
      break
    end
  end
end

--- @param bufnr integer
--- @param top integer
--- @param bot integer
--- @param clear? boolean
local function apply_win_signs(bufnr, top, bot, clear)
  local bcache = assert(cache[bufnr])
  local untracked = bcache.git_obj.object_name == nil
  apply_win_signs0(bufnr, signs_normal, bcache.hunks, top, bot, clear, untracked)
  if signs_staged then
    apply_win_signs0(
      bufnr,
      signs_staged,
      bcache.hunks_staged,
      top,
      bot,
      clear,
      false,
      function(lnum)
        return not signs_normal:contains(bufnr, lnum)
      end
    )
  end
end

--- @param blame table<integer,Gitsigns.BlameInfo?>?
--- @param first integer
--- @param last_orig integer
--- @param last_new integer
local function on_lines_blame(blame, first, last_orig, last_new)
  if not blame then
    return
  end

  if last_new < last_orig then
    util.list_remove(blame, last_new + 1, last_orig)
  elseif last_new > last_orig then
    util.list_insert(blame, last_orig + 1, last_new)
  end

  for i = first + 1, last_new do
    blame[i] = nil
  end
end

--- @param buf integer
--- @param first integer
--- @param last_orig integer
--- @param last_new integer
--- @return true?
function M.on_lines(buf, first, last_orig, last_new)
  local bcache = cache[buf]
  if not bcache then
    log.dprint('Cache for buffer was nil. Detaching')
    return true
  end

  on_lines_blame(bcache.blame, first, last_orig, last_new)

  signs_normal:on_lines(buf, first, last_orig, last_new)
  if signs_staged then
    signs_staged:on_lines(buf, first, last_orig, last_new)
  end

  -- Signs in changed regions get invalidated so we need to force a redraw if
  -- any signs get removed.
  if bcache.hunks and signs_normal:contains(buf, first, last_new) then
    -- Force a sign redraw on the next update (fixes #521)
    bcache.force_next_update = true
  end

  if signs_staged then
    if bcache.hunks_staged and signs_staged:contains(buf, first, last_new) then
      -- Force a sign redraw on the next update (fixes #521)
      bcache.force_next_update = true
    end
  end

  M.update_debounced(buf)
end

local ns = api.nvim_create_namespace('gitsigns')

--- @param bufnr integer
--- @param row integer
local function apply_word_diff(bufnr, row)
  -- Don't run on folded lines
  if vim.fn.foldclosed(row + 1) ~= -1 then
    return
  end

  local bcache = cache[bufnr]

  if not bcache or not bcache.hunks then
    return
  end

  local line = api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
  if not line then
    -- Invalid line
    return
  end

  local lnum = row + 1

  local hunk = Hunks.find_hunk(lnum, bcache.hunks)
  if not hunk then
    -- No hunk at line
    return
  end

  if hunk.added.count ~= hunk.removed.count then
    -- Only word diff if added count == removed
    return
  end

  local pos = lnum - hunk.added.start + 1

  local added_line = assert(hunk.added.lines[pos])
  local removed_line = assert(hunk.removed.lines[pos])

  local _, added_regions = require('gitsigns.diff_int').run_word_diff(
    { removed_line },
    { added_line }
  )

  local cols = #line

  for _, region in ipairs(added_regions) do
    local rtype, scol, ecol = region[2], region[3] - 1, region[4] - 1
    if ecol == scol then
      -- Make sure region is at least 1 column wide so deletes can be shown
      ecol = scol + 1
    end

    local hl_group = rtype == 'add' and 'GitSignsAddLnInline'
      or rtype == 'change' and 'GitSignsChangeLnInline'
      or 'GitSignsDeleteLnInline'

    local opts = {
      ephemeral = true,
      priority = 1000,
    }

    if ecol > cols and ecol == scol + 1 then
      -- delete on last column, use virtual text instead
      opts.virt_text = { { ' ', hl_group } }
      opts.virt_text_pos = 'overlay'
    else
      opts.end_col = ecol
      opts.hl_group = hl_group
    end

    api.nvim_buf_set_extmark(bufnr, ns, row, scol, opts)
    util.redraw({ buf = bufnr, range = { row, row + 1 } })
  end
end

local ns_rm = api.nvim_create_namespace('gitsigns_removed')

local VIRT_LINE_LEN = 300

--- @param bufnr integer
local function clear_deleted(bufnr)
  local marks = api.nvim_buf_get_extmarks(bufnr, ns_rm, 0, -1, {})
  for _, mark in ipairs(marks) do
    api.nvim_buf_del_extmark(bufnr, ns_rm, mark[1])
  end
end

--- @param bufnr integer
--- @param nsd integer
--- @param hunk Gitsigns.Hunk.Hunk
local function show_deleted(bufnr, nsd, hunk)
  local virt_lines = {} --- @type [string, string][][]

  for i, line in ipairs(hunk.removed.lines) do
    local vline = {} --- @type [string, string][]
    local last_ecol = 1

    if config.word_diff then
      local regions = require('gitsigns.diff_int').run_word_diff(
        { hunk.removed.lines[i] },
        { hunk.added.lines[i] }
      )

      for _, region in ipairs(regions) do
        local rline, scol, ecol = region[1], region[3], region[4]
        if rline > 1 then
          break
        end
        vline[#vline + 1] = { line:sub(last_ecol, scol - 1), 'GitSignsDeleteVirtLn' }
        vline[#vline + 1] = { line:sub(scol, ecol - 1), 'GitSignsDeleteVirtLnInline' }
        last_ecol = ecol
      end
    end

    if #line > 0 then
      vline[#vline + 1] = { line:sub(last_ecol, -1), 'GitSignsDeleteVirtLn' }
    end

    -- Add extra padding so the entire line is highlighted
    local padding = string.rep(' ', VIRT_LINE_LEN - #line)
    vline[#vline + 1] = { padding, 'GitSignsDeleteVirtLn' }

    virt_lines[i] = vline
  end

  local topdelete = hunk.added.start == 0 and hunk.type == 'delete'

  local row = topdelete and 0 or hunk.added.start - 1
  api.nvim_buf_set_extmark(bufnr, nsd, row, -1, {
    virt_lines = virt_lines,
    -- TODO(lewis6991): Note virt_lines_above doesn't work on row 0 neovim/neovim#16166
    virt_lines_above = hunk.type ~= 'delete' or topdelete,
  })
end

--- @param bufnr integer
--- @param hunks? Gitsigns.Hunk.Hunk[]
local function update_show_deleted(bufnr, hunks)
  clear_deleted(bufnr)
  if config.show_deleted then
    for _, hunk in ipairs(hunks or {}) do
      show_deleted(bufnr, ns_rm, hunk)
    end
  end
end

--- @async
--- Ensure updates cannot be interleaved.
--- Since updates are asynchronous we need to make sure an update isn't performed
--- whilst another one is in progress. If this happens then schedule another
--- update after the current one has completed.
--- @param bufnr integer
M.update = throttle_by_id(function(bufnr)
  local bcache = cache[bufnr]
  if not bcache or not bcache:schedule() then
    return
  end
  bcache.update_lock = true

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

  bcache.hunks = run_diff(assert(bcache.compare_text), buftext)
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
  if
    bcache.force_next_update
    or Hunks.compare_heads(bcache.hunks, old_hunks)
    or Hunks.compare_heads(bcache.hunks_staged, old_hunks_staged)
  then
    -- Apply signs to the window. Other signs will be added by the decoration
    -- provider as they are drawn.
    apply_win_signs(bufnr, vim.fn.line('w0'), vim.fn.line('w$'), true)

    update_show_deleted(bufnr, bcache.hunks)
    bcache.force_next_update = false

    local summary = Hunks.get_summary(bcache.hunks)
    summary.head = git_obj.repo.abbrev_head
    Status:update(bufnr, summary)
  end
  bcache.update_lock = nil
end, true)

M.update_debounced = debounce_trailing(function()
  return config.update_debounce
end, async.create(1, M.update))

--- @param bufnr integer
--- @param keep_signs? boolean
function M.detach(bufnr, keep_signs)
  if not keep_signs then
    -- Remove all signs
    signs_normal:remove(bufnr)
    if signs_staged then
      signs_staged:remove(bufnr)
    end
  end
end

function M.reset_signs()
  -- Remove all signs
  signs_normal:reset()
  signs_staged:reset()
end

--- @param bufnr integer
--- @param topline integer
--- @param botline_guess integer
--- @return false?
local function on_win(bufnr, topline, botline_guess)
  local bcache = cache[bufnr]
  if not bcache or not bcache.hunks then
    return false
  end
  local botline = math.min(botline_guess, api.nvim_buf_line_count(bufnr))

  apply_win_signs(bufnr, topline + 1, botline + 1)

  if not (config.word_diff and config.diff_opts.internal) then
    return false
  end
end

function M.setup()
  -- Calling this before any await calls will stop nvim's intro messages being
  -- displayed
  api.nvim_set_decoration_provider(ns, {
    on_win = function(_, _winid, bufnr, topline, botline)
      return on_win(bufnr, topline, botline)
    end,
    on_line = function(_, _winid, bufnr, row)
      apply_word_diff(bufnr, row)
    end,
  })

  Config.subscribe({ 'signcolumn', 'numhl', 'linehl', 'show_deleted' }, function()
    -- Remove all signs
    M.reset_signs()

    for k, v in pairs(cache) do
      v:invalidate(true)
      M.update_debounced(k)
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
      M.update_debounced(buf)
    end,
  })
end

return M
