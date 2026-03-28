local cache = require('gitsigns.cache').cache
local config = require('gitsigns.config').config
local DeletedPreview = require('gitsigns.deleted_preview')
local HunkPreview = require('gitsigns.hunk_preview')
local popup = require('gitsigns.popup')

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

--- @param bcache Gitsigns.CacheEntry
--- @return Gitsigns.Hunk.Hunk[] hunks
--- @return table<Gitsigns.Hunk.Hunk, boolean> staged_lookup
local function merge_hunks_with_staged(bcache)
  local hunks = {} --- @type Gitsigns.Hunk.Hunk[]
  local staged_lookup = {} --- @type table<Gitsigns.Hunk.Hunk, boolean>

  for _, hunk in ipairs(bcache.hunks or {}) do
    hunks[#hunks + 1] = hunk
  end

  for _, hunk in ipairs(bcache.hunks_staged or {}) do
    hunks[#hunks + 1] = hunk
    staged_lookup[hunk] = true
  end

  table.sort(hunks, function(a, b)
    if a.added.start == b.added.start then
      return a.vend < b.vend
    end
    return a.added.start < b.added.start
  end)

  return hunks, staged_lookup
end

--- @param bcache Gitsigns.CacheEntry
--- @return Gitsigns.Hunk.Hunk? hunk
--- @return integer? index
--- @return boolean? staged
--- @return integer total
local function get_cursor_hunk_with_staged(bcache)
  local hunks, staged_lookup = merge_hunks_with_staged(bcache)

  local hunk, index = bcache:get_cursor_hunk(hunks)
  if not hunk then
    return nil, nil, nil, #hunks
  end

  return hunk, index, staged_lookup[hunk] == true, #hunks
end

local function clear_preview_inline(bufnr)
  api.nvim_buf_clear_namespace(bufnr, ns_inline, 0, -1)
end

--- @param keys string
local function feedkeys(keys)
  local cy = api.nvim_replace_termcodes(keys, true, false, true)
  api.nvim_feedkeys(cy, 'n', false)
end

--- @param bufnr integer
--- @param hunk Gitsigns.Hunk.Hunk
--- @return Gitsigns.Hunk.Node
local function staged_added_node(bufnr, hunk)
  local top = hunk.added.start

  for _, unstaged in ipairs(assert(cache[bufnr]).hunks or {}) do
    local delta = (unstaged.added.count - unstaged.removed.count) --[[@as integer]]
    if delta ~= 0 and top > unstaged.vend then
      top = top - delta
    end
  end

  return {
    start = top,
    count = hunk.added.count,
    lines = hunk.added.lines,
    no_nl_at_eof = hunk.added.no_nl_at_eof,
  }
end

--- @param bufnr integer
--- @param hunk Gitsigns.Hunk.Hunk
--- @param staged boolean?
--- @param index integer
--- @param total integer
--- @return Gitsigns.LineSpec[]
local function build_popup_preview_linespec(bufnr, hunk, staged, index, total)
  --- @type Gitsigns.LineSpec[]
  local linespec = {
    { { ('Hunk %d of %d'):format(index, total), 'Title' } },
  }
  local bcache = assert(cache[bufnr])
  local removed_source = assert(staged and bcache.compare_text_head or bcache.compare_text)
  local added_source = staged and assert(bcache.compare_text) or bufnr
  local added_node = staged and staged_added_node(bufnr, hunk) or hunk.added
  vim.list_extend(
    linespec,
    HunkPreview.prepare_linespec_for_hunk(bufnr, hunk, removed_source, added_source, added_node)
  )
  return linespec
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
    local cr_at_eol_change = rtype == 'change'
      and vim.endswith(assert(hunk.added.lines[offset + 1]), '\r')

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

--- Preview the hunk at the cursor position in a floating
--- window. If the preview is already open, calling this
--- will cause the window to get focus.
function M.preview_hunk()
  if popup.is_open('hunk') then
    popup.focus_open('hunk')
    return
  end

  local bcache = cache[current_buf()]
  if not bcache then
    return
  end

  local hunk, index, staged, total = get_cursor_hunk_with_staged(bcache)

  if not hunk then
    return
  end

  assert(index)

  local linespec = build_popup_preview_linespec(bcache.bufnr, hunk, staged, index, total)
  popup.create(linespec, config.preview_config, 'hunk')
end

--- Preview the hunk at the cursor position inline in the buffer.
--- @async
--- @return integer? markid
function M.preview_hunk_inline()
  local bufnr = current_buf()

  local hunk, staged = get_hunk_with_staged(bufnr, true)

  if not hunk then
    return
  end

  clear_preview_inline(bufnr)

  local preview_id --- @type integer?
  show_added(bufnr, ns_inline, hunk)
  if hunk.removed.count > 0 then
    preview_id = DeletedPreview.place_inline_preview_lines(bufnr, ns_inline, hunk, staged, {
      win = api.nvim_get_current_win(),
      lno_hl = true,
      leftcol = true,
      word_diff = true,
    })
  end

  api.nvim_create_autocmd({ 'CursorMoved', 'InsertEnter', 'BufLeave' }, {
    buffer = bufnr,
    desc = 'Clear gitsigns inline preview',
    callback = function()
      clear_preview_inline(bufnr)
    end,
    once = true,
  })

  -- Virtual lines will be hidden if they are placed on the top row, so
  -- automatically scroll the viewport.
  if preview_id and hunk.added.start <= 1 then
    feedkeys(hunk.removed.count .. '<C-y>')
  end

  return preview_id
end

--- @param bufnr integer
--- @return boolean
function M.has_preview_inline(bufnr)
  return #api.nvim_buf_get_extmarks(bufnr, ns_inline, 0, -1, { limit = 1 }) > 0
end

return M
