local async = require('gitsigns.async')

local gs_cache = require('gitsigns.cache')
local cache = gs_cache.cache

local Signs = require('gitsigns.signs')
local Status = require('gitsigns.status')

local debounce_trailing = require('gitsigns.debounce').debounce_trailing
local throttle_by_id = require('gitsigns.debounce').throttle_by_id

local log = require('gitsigns.debug.log')
local dprint = log.dprint
local dprintf = log.dprintf

local system = require('gitsigns.system')
local util = require('gitsigns.util')
local run_diff = require('gitsigns.diff')

local gs_hunks = require('gitsigns.hunks')

local config = require('gitsigns.config').config

local api = vim.api

local signs_normal --- @type Gitsigns.Signs
local signs_staged --- @type Gitsigns.Signs

local M = {}

--- @param bufnr integer
--- @param signs Gitsigns.Signs
--- @param hunks Gitsigns.Hunk.Hunk[]
--- @param top integer
--- @param bot integer
--- @param clear boolean
--- @param untracked boolean
local function apply_win_signs0(bufnr, signs, hunks, top, bot, clear, untracked)
  if clear then
    signs:remove(bufnr) -- Remove all signs
  end

  for i, hunk in ipairs(hunks or {}) do
    -- To stop the sign column width changing too much, if there are signs to be
    -- added but none of them are visible in the window, then make sure to add at
    -- least one sign. Only do this on the first call after an update when we all
    -- the signs have been cleared.
    if clear and i == 1 then
      signs:add(bufnr, gs_hunks.calc_signs(hunk, hunk.added.start, hunk.added.start, untracked))
    end

    if top <= hunk.vend and bot >= hunk.added.start then
      signs:add(bufnr, gs_hunks.calc_signs(hunk, top, bot, untracked))
    end
    if hunk.added.start > bot then
      break
    end
  end
end

--- @param bufnr integer
--- @param top integer
--- @param bot integer
--- @param clear boolean
local function apply_win_signs(bufnr, top, bot, clear)
  local bcache = cache[bufnr]
  if not bcache then
    return
  end

  local untracked = bcache.git_obj.object_name == nil and not bcache.base
  apply_win_signs0(bufnr, signs_normal, bcache.hunks, top, bot, clear, untracked)
  if signs_staged then
    apply_win_signs0(bufnr, signs_staged, bcache.hunks_staged, top, bot, clear, false)
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

  if last_new ~= last_orig then
    if last_new < last_orig then
      util.list_remove(blame, last_new, last_orig)
    else
      util.list_insert(blame, last_orig, last_new)
    end
  end

  for i = math.min(first + 1, last_new), math.max(first + 1, last_new) do
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
    dprint('Cache for buffer was nil. Detaching')
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

  local hunk = gs_hunks.find_hunk(lnum, bcache.hunks)
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
    api.nvim__buf_redraw_range(bufnr, row, row + 1)
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
function M.show_deleted(bufnr, nsd, hunk)
  local virt_lines = {} --- @type {[1]: string, [2]: string}[][]

  for i, line in ipairs(hunk.removed.lines) do
    local vline = {} --- @type {[1]: string, [2]: string}[]
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

--- @param win integer
--- @param lnum integer
--- @param width integer
--- @return string str
--- @return {group:string, start:integer}[]? highlights
local function build_lno_str(win, lnum, width)
  local has_col, statuscol =
    pcall(api.nvim_get_option_value, 'statuscolumn', { win = win, scope = 'local' })
  if has_col and statuscol and statuscol ~= '' then
    local ok, data = pcall(api.nvim_eval_statusline, statuscol, {
      winid = win,
      use_statuscol_lnum = lnum,
      highlights = true,
    })
    if ok then
      return data.str, data.highlights
    end
  end
  return string.format('%' .. width .. 'd', lnum)
end

--- @param bufnr integer
--- @param nsd integer
--- @param hunk Gitsigns.Hunk.Hunk
--- @param staged boolean?
--- @return integer winid
function M.show_deleted_in_float(bufnr, nsd, hunk, staged)
  local cwin = api.nvim_get_current_win()
  local virt_lines = {} --- @type {[1]: string, [2]: string}[][]
  local textoff = vim.fn.getwininfo(cwin)[1].textoff --[[@as integer]]
  for i = 1, hunk.removed.count do
    local sc = build_lno_str(cwin, hunk.removed.start + i, textoff - 1)
    virt_lines[i] = { { sc, 'LineNr' } }
  end

  local topdelete = hunk.added.start == 0 and hunk.type == 'delete'
  local virt_lines_above = hunk.type ~= 'delete' or topdelete

  local row = topdelete and 0 or hunk.added.start - 1
  api.nvim_buf_set_extmark(bufnr, nsd, row, -1, {
    virt_lines = virt_lines,
    -- TODO(lewis6991): Note virt_lines_above doesn't work on row 0 neovim/neovim#16166
    virt_lines_above = virt_lines_above,
    virt_lines_leftcol = true,
  })

  local bcache = cache[bufnr]
  local pbufnr = api.nvim_create_buf(false, true)
  local text = staged and bcache.compare_text_head or bcache.compare_text
  api.nvim_buf_set_lines(pbufnr, 0, -1, false, assert(text))

  local width = api.nvim_win_get_width(0)

  local bufpos_offset = virt_lines_above and not topdelete and 1 or 0

  local pwinid = api.nvim_open_win(pbufnr, false, {
    relative = 'win',
    win = cwin,
    width = width - textoff,
    height = hunk.removed.count,
    anchor = 'SW',
    bufpos = { hunk.added.start - bufpos_offset, 0 },
    style = 'minimal',
  })

  vim.bo[pbufnr].filetype = vim.bo[bufnr].filetype
  vim.bo[pbufnr].bufhidden = 'wipe'
  vim.wo[pwinid].scrolloff = 0

  api.nvim_win_call(pwinid, function()
    -- Expand folds
    vim.cmd('normal ' .. 'zR')

    -- Navigate to hunk
    vim.cmd('normal ' .. tostring(hunk.removed.start) .. 'gg')
    vim.cmd('normal ' .. vim.api.nvim_replace_termcodes('z<CR>', true, false, true))
  end)

  local last_lnum = api.nvim_buf_line_count(bufnr)

  -- Apply highlights

  for i = hunk.removed.start, hunk.removed.start + hunk.removed.count do
    api.nvim_buf_set_extmark(pbufnr, nsd, i - 1, 0, {
      hl_group = 'GitSignsDeleteVirtLn',
      hl_eol = true,
      end_row = i,
      strict = i == last_lnum,
      priority = 1000,
    })
  end

  local removed_regions =
    require('gitsigns.diff_int').run_word_diff(hunk.removed.lines, hunk.added.lines)

  for _, region in ipairs(removed_regions) do
    local start_row = (hunk.removed.start - 1) + (region[1] - 1)
    local start_col = region[3] - 1
    local end_col = region[4] - 1
    api.nvim_buf_set_extmark(pbufnr, nsd, start_row, start_col, {
      hl_group = 'GitSignsDeleteVirtLnInline',
      end_col = end_col,
      end_row = start_row,
      priority = 1001,
    })
  end

  return pwinid
end

--- @param bufnr integer
--- @param nsw integer
--- @param hunk Gitsigns.Hunk.Hunk
function M.show_added(bufnr, nsw, hunk)
  local start_row = hunk.added.start - 1

  for offset = 0, hunk.added.count - 1 do
    local row = start_row + offset
    api.nvim_buf_set_extmark(bufnr, nsw, row, 0, {
      end_row = row + 1,
      hl_group = 'GitSignsAddPreview',
      hl_eol = true,
      priority = 1000,
    })
  end

  local _, added_regions =
    require('gitsigns.diff_int').run_word_diff(hunk.removed.lines, hunk.added.lines)

  for _, region in ipairs(added_regions) do
    local offset, rtype, scol, ecol = region[1] - 1, region[2], region[3] - 1, region[4] - 1

    -- Special case to handle cr at eol in buffer but not in show text
    local cr_at_eol_change = rtype == 'change' and vim.endswith(hunk.added.lines[offset + 1], '\r')

    api.nvim_buf_set_extmark(bufnr, nsw, start_row + offset, scol, {
      end_col = ecol,
      strict = not cr_at_eol_change,
      hl_group = rtype == 'add' and 'GitSignsAddInline'
        or rtype == 'change' and 'GitSignsChangeInline'
        or 'GitSignsDeleteInline',
      priority = 1001,
    })
  end
end

--- @param bufnr integer
local function update_show_deleted(bufnr)
  local bcache = cache[bufnr]

  clear_deleted(bufnr)
  if config.show_deleted then
    for _, hunk in ipairs(bcache.hunks or {}) do
      M.show_deleted(bufnr, ns_rm, hunk)
    end
  end
end

--- @param bufnr? integer
--- @param check_compare_text? boolean
--- @param cb function
M.buf_check = async.wrap(function(bufnr, check_compare_text, cb)
  vim.schedule(function()
    if bufnr then
      if not api.nvim_buf_is_valid(bufnr) then
        dprint('Buffer not valid, aborting')
        return
      end
      if not cache[bufnr] then
        dprint('Has detached, aborting')
        return
      end
      if check_compare_text and not cache[bufnr].compare_text then
        dprint('compare_text was invalid, aborting')
        return
      end
    end
    cb()
  end)
end, 3)

local update_cnt = 0

--- Ensure updates cannot be interleaved.
--- Since updates are asynchronous we need to make sure an update isn't performed
--- whilst another one is in progress. If this happens then schedule another
--- update after the current one has completed.
--- @param bufnr integer
M.update = throttle_by_id(function(bufnr)
  local __FUNC__ = 'update'
  M.buf_check(bufnr)
  local bcache = cache[bufnr]
  local old_hunks, old_hunks_staged = bcache.hunks, bcache.hunks_staged
  bcache.hunks, bcache.hunks_staged = nil, nil

  local git_obj = bcache.git_obj

  local compare_rev = bcache:get_compare_rev()

  local file_mode = compare_rev == 'FILE'

  if not bcache.compare_text or config._refresh_staged_on_update or file_mode then
    bcache.compare_text = git_obj:get_show_text(compare_rev)
    M.buf_check(bufnr, true)
  end

  local buftext = util.buf_lines(bufnr)

  bcache.hunks = run_diff(bcache.compare_text, buftext)
  M.buf_check(bufnr)

  if config._signs_staged_enable and not file_mode then
    if not bcache.compare_text_head or config._refresh_staged_on_update then
      local staged_compare_rev = bcache.commit and string.format('%s^', bcache.commit) or 'HEAD'
      bcache.compare_text_head = git_obj:get_show_text(staged_compare_rev)
      M.buf_check(bufnr, true)
    end
    local hunks_head = run_diff(bcache.compare_text_head, buftext)
    M.buf_check(bufnr)
    bcache.hunks_staged = gs_hunks.filter_common(hunks_head, bcache.hunks)
  end

  -- Note the decoration provider may have invalidated bcache.hunks at this
  -- point
  if
    bcache.force_next_update
    or gs_hunks.compare_heads(bcache.hunks, old_hunks)
    or gs_hunks.compare_heads(bcache.hunks_staged, old_hunks_staged)
  then
    -- Apply signs to the window. Other signs will be added by the decoration
    -- provider as they are drawn.
    apply_win_signs(bufnr, vim.fn.line('w0'), vim.fn.line('w$'), true)

    update_show_deleted(bufnr)
    bcache.force_next_update = false

    api.nvim_exec_autocmds('User', {
      pattern = 'GitSignsUpdate',
      modeline = false,
    })
  end

  local summary = gs_hunks.get_summary(bcache.hunks)
  summary.head = git_obj.repo.abbrev_head
  Status:update(bufnr, summary)

  update_cnt = update_cnt + 1

  dprintf('updates: %s, jobs: %s', update_cnt, system.job_cnt)
end, true)

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
  if signs_normal then
    signs_normal:reset()
  end
  if signs_staged then
    signs_staged:reset()
  end
end

--- @param _cb 'win'
--- @param _winid integer
--- @param bufnr integer
--- @param topline integer
--- @param botline_guess integer
--- @return false?
local function on_win(_cb, _winid, bufnr, topline, botline_guess)
  local bcache = cache[bufnr]
  if not bcache or not bcache.hunks then
    return false
  end
  local botline = math.min(botline_guess, api.nvim_buf_line_count(bufnr))

  apply_win_signs(bufnr, topline + 1, botline + 1, false)

  if not (config.word_diff and config.diff_opts.internal) then
    return false
  end
end

--- @param _cb 'line'
--- @param _winid integer
--- @param bufnr integer
--- @param row integer
local function on_line(_cb, _winid, bufnr, row)
  apply_word_diff(bufnr, row)
end

function M.setup()
  -- Calling this before any await calls will stop nvim's intro messages being
  -- displayed
  api.nvim_set_decoration_provider(ns, {
    on_win = on_win,
    on_line = on_line,
  })

  signs_normal = Signs.new(config.signs)
  if config._signs_staged_enable then
    signs_staged = Signs.new(config._signs_staged, 'staged')
  end

  M.update_debounced = debounce_trailing(config.update_debounce, async.void(M.update))
end

return M
