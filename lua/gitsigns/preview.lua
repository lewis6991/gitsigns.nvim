local cache = require('gitsigns.cache').cache
local config = require('gitsigns.config').config
local popup = require('gitsigns.popup')
local Hunks = require('gitsigns.hunks')

local api = vim.api
local current_buf = api.nvim_get_current_buf

--- @class gitsigns.preview
local M = {}

local ns_inline = api.nvim_create_namespace('gitsigns_preview_inline')

--- @async
--- @param bufnr integer
--- @param greedy? boolean
--- @return Gitsigns.Hunk.Hunk? hunk
--- @return boolean? staged
local function get_hunk_with_staged(bufnr, greedy)
  local bcache = cache[bufnr]
  if not bcache then
    return
  end

  local hunk = bcache:get_hunk(nil, greedy, false)
  if hunk then
    return hunk, false
  end

  hunk = bcache:get_hunk(nil, greedy, true)
  if hunk then
    return hunk, true
  end
end

local function clear_preview_inline(bufnr)
  api.nvim_buf_clear_namespace(bufnr, ns_inline, 0, -1)
end

--- @param keys string
local function feedkeys(keys)
  local cy = api.nvim_replace_termcodes(keys, true, false, true)
  api.nvim_feedkeys(cy, 'n', false)
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
    --- @cast statuscol string
    local ok, data = pcall(api.nvim_eval_statusline, statuscol, {
      winid = win,
      use_statuscol_lnum = lnum,
      highlights = true,
    })
    if ok then
      local data_str = data.str --[[@as string]]
      return data_str, data.highlights
    end
  end
  return string.format('%' .. width .. 'd', lnum)
end

--- @param bufnr integer
--- @param nsw integer
--- @param hunk Gitsigns.Hunk.Hunk
local function show_added(bufnr, nsw, hunk)
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
--- @param nsd integer
--- @param hunk Gitsigns.Hunk.Hunk
--- @param staged boolean?
--- @return integer winid
local function show_deleted_in_float(bufnr, nsd, hunk, staged)
  local cwin = api.nvim_get_current_win()
  local virt_lines = {} --- @type [string, string][][]
  local textoff = assert(vim.fn.getwininfo(cwin)[1]).textoff --[[@as integer]]
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

  local bcache = assert(cache[bufnr])
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
    border = 'none',
  })

  vim.bo[pbufnr].filetype = vim.bo[bufnr].filetype
  vim.bo[pbufnr].bufhidden = 'wipe'
  vim.wo[pwinid].scrolloff = 0

  api.nvim_win_call(pwinid, function()
    -- Disable folds
    vim.wo.foldenable = false

    -- Navigate to hunk
    vim.cmd('normal! ' .. tostring(hunk.removed.start) .. 'gg')
    vim.cmd('normal! ' .. vim.api.nvim_replace_termcodes('z<CR>', true, false, true))
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

local function noautocmd(f)
  return function()
    local ei = vim.o.eventignore
    vim.o.eventignore = 'all'
    f()
    vim.o.eventignore = ei
  end
end

--- Preview the hunk at the cursor position in a floating
--- window. If the preview is already open, calling this
--- will cause the window to get focus.
M.preview_hunk = noautocmd(function()
  -- Wrap in noautocmd so vim-repeat continues to work

  if popup.focus_open('hunk') then
    return
  end

  local bufnr = current_buf()
  local bcache = cache[bufnr]
  if not bcache then
    return
  end

  local hunk, index = bcache:get_cursor_hunk()

  if not hunk then
    return
  end

  --- @type Gitsigns.LineSpec
  local preview_linespec = {
    { { 'Hunk <hunk_no> of <num_hunks>', 'Title' } },
  }
  vim.list_extend(preview_linespec, Hunks.linespec_for_hunk(hunk, vim.bo[bufnr].fileformat))

  local lines_spec = popup.lines_format(preview_linespec, {
    hunk_no = index,
    num_hunks = #bcache.hunks,
  })

  popup.create(lines_spec, config.preview_config, 'hunk')
end)

--- Preview the hunk at the cursor position inline in the buffer.
--- @async
function M.preview_hunk_inline()
  local bufnr = current_buf()

  local hunk, staged = get_hunk_with_staged(bufnr, true)

  if not hunk then
    return
  end

  clear_preview_inline(bufnr)

  local winid --- @type integer
  show_added(bufnr, ns_inline, hunk)
  if hunk.removed.count > 0 then
    winid = show_deleted_in_float(bufnr, ns_inline, hunk, staged)
  end

  api.nvim_create_autocmd({ 'CursorMoved', 'InsertEnter' }, {
    buffer = bufnr,
    desc = 'Clear gitsigns inline preview',
    callback = function()
      if winid then
        pcall(api.nvim_win_close, winid, true)
      end
      clear_preview_inline(bufnr)
    end,
    once = true,
  })

  -- Virtual lines will be hidden if they are placed on the top row, so
  -- automatically scroll the viewport.
  if hunk.added.start <= 1 then
    feedkeys(hunk.removed.count .. '<C-y>')
  end
end

--- @param bufnr integer
--- @return boolean
function M.has_preview_inline(bufnr)
  return #api.nvim_buf_get_extmarks(bufnr, ns_inline, 0, -1, { limit = 1 }) > 0
end

return M
