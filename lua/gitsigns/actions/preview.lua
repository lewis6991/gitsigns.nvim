local async = require('gitsigns.async')
local cache = require('gitsigns.cache').cache
local config = require('gitsigns.config').config
local DeletedPreview = require('gitsigns.deleted_preview')
local HunkPreview = require('gitsigns.hunk_preview')
local Hunks = require('gitsigns.hunks')
local popup = require('gitsigns.popup')

local api = vim.api
local current_buf = api.nvim_get_current_buf

--- @class gitsigns.preview
local M = {}

local ns_inline = api.nvim_create_namespace('gitsigns_preview_inline')
local window_ns_supported = api.nvim__ns_set ~= nil
local inline_bufnr --- @type integer?
local inline_winid --- @type integer?

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

  local unstaged_hunk = bcache:get_hunk(nil, greedy, false)
  if unstaged_hunk then
    return unstaged_hunk, false
  end

  local staged_hunk = bcache:get_hunk(nil, greedy, true)
  if staged_hunk then
    return staged_hunk, true
  end
end

--- Get the greedy hunk at the cursor for popup preview. Prefer unstaged hunks
--- and only fall back to staged hunks if no unstaged hunk matches. The
--- returned index and total belong to the selected list.
--- @param bcache Gitsigns.CacheEntry
--- @async
--- @return Gitsigns.Hunk.Hunk? hunk
--- @return integer? index
--- @return boolean? staged
--- @return integer total
local function get_hunk_at_cursor(bcache)
  --- @type Gitsigns.Hunk.Hunk[]
  local hunks = bcache:get_hunks(true, false) or {}
  local hunk, index = bcache:get_cursor_hunk(hunks)
  if hunk then
    return hunk, index, false, #hunks
  end

  --- @type Gitsigns.Hunk.Hunk[]
  local hunks_head = bcache:get_hunks(true, true) or {}
  --- @type Gitsigns.Hunk.Hunk[]
  local hunks_staged = Hunks.filter_common(hunks_head, hunks) or {}
  hunk, index = bcache:get_cursor_hunk(hunks_staged)
  if hunk then
    return hunk, index, true, #hunks_staged
  end

  return nil, nil, nil, 0
end

local function clear_preview_inline(bufnr)
  api.nvim_buf_clear_namespace(bufnr, ns_inline, 0, -1)
  if inline_bufnr == bufnr then
    inline_bufnr = nil
    inline_winid = nil
    if window_ns_supported then
      api.nvim__ns_set(ns_inline, { wins = {} })
    end
  end
end

--- @param keys string
local function feedkeys(keys)
  local cy = api.nvim_replace_termcodes(keys, true, false, true)
  api.nvim_feedkeys(cy, 'nx', false)
end

--- Translate a staged hunk's added node from current-buffer coordinates into
--- index coordinates by subtracting the line deltas introduced by unstaged
--- hunks above it.
--- @param bufnr integer
--- @param hunk Gitsigns.Hunk.Hunk
--- @return Gitsigns.Hunk.Node
local function index_added_node_for_staged_hunk(bufnr, hunk)
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

  local hunk, index, staged, total = async.run(get_hunk_at_cursor, bcache):wait()

  if not hunk or not index then
    return
  end

  --- @type Gitsigns.LineSpec[]
  local linespec = {
    { { ('Hunk %d of %d'):format(index, total), 'Title' } },
  }

  if staged then
    vim.list_extend(
      linespec,
      HunkPreview.linespec_for_hunk(
        bcache.bufnr,
        hunk,
        assert(bcache.compare_text_head),
        assert(bcache.compare_text),
        index_added_node_for_staged_hunk(bcache.bufnr, hunk)
      )
    )
  else
    vim.list_extend(
      linespec,
      HunkPreview.linespec_for_hunk(
        bcache.bufnr,
        hunk,
        assert(bcache.compare_text),
        bcache.bufnr,
        hunk.added
      )
    )
  end

  popup.create(linespec, config.preview_config, 'hunk')
end

--- Preview the hunk at the cursor position inline in the buffer.
--- @async
--- @return integer? markid
function M.preview_hunk_inline()
  local bufnr = current_buf()
  local winid = api.nvim_get_current_win()

  local hunk, staged = get_hunk_with_staged(bufnr, true)

  if not hunk then
    return
  end

  if inline_bufnr and (inline_bufnr ~= bufnr or inline_winid ~= winid) then
    api.nvim_buf_clear_namespace(inline_bufnr, ns_inline, 0, -1)
  end

  clear_preview_inline(bufnr)

  if window_ns_supported then
    api.nvim__ns_set(ns_inline, { wins = { winid } })
  end

  inline_bufnr = bufnr
  inline_winid = winid

  local preview_id --- @type integer?
  show_added(bufnr, ns_inline, hunk)
  if hunk.removed.count > 0 then
    preview_id = DeletedPreview.place_inline_preview_lines(bufnr, ns_inline, hunk, staged, {
      win = winid,
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
  if hunk.removed.count > 0 and hunk.added.start <= 1 then
    feedkeys(hunk.removed.count .. '<C-y>')
  end

  return preview_id
end

--- @param bufnr integer
--- @return boolean
function M.has_preview_inline(bufnr)
  if inline_bufnr ~= bufnr then
    return false
  end

  if window_ns_supported and inline_winid ~= api.nvim_get_current_win() then
    return false
  end

  return #api.nvim_buf_get_extmarks(bufnr, ns_inline, 0, -1, { limit = 1 }) > 0
end

return M
