local cache = require('gitsigns.cache').cache
local config = require('gitsigns.config').config
local HunkPreview = require('gitsigns.hunk_preview')
local Virt = require('gitsigns.render.virt')
local Inspect = require('gitsigns.inspect')
local util = require('gitsigns.util')

local api = vim.api

local M = {}
local window_ns_supported = api.nvim__ns_set ~= nil
local ns_removed = api.nvim_create_namespace('gitsigns_removed')

local VIRT_LINE_LEN = 300
local REMOVED_VIRT_LINE_HL = 'GitSignsDeleteVirtLn'
local REMOVED_INLINE_HL = 'GitSignsDeleteVirtLnInLine'
local VIRT_LINES_OVERFLOW = vim.fn.has('nvim-0.11') == 1 and 'scroll' or nil
local win_ns = {} --- @type table<integer, {ns: integer, bufnr?: integer}>
local states = {} --- @type table<integer, {hunks: Gitsigns.Hunk.Hunk[], lines: table<Gitsigns.Hunk.Hunk, Gitsigns.CapturedLine[]>, source_bufs: table<string, Gitsigns.HunkPreview.SourceBuf>, pending?: table<Gitsigns.Hunk.Hunk, true>, scheduled?: boolean}>

--- @param str string
--- @param highlights {group?:string, groups?:string[], start:integer}[]
--- @return Gitsigns.VirtTextChunk[]
local function chunks_from_statusline(str, highlights)
  local chunks = {} --- @type Gitsigns.VirtTextChunk[]

  if #highlights == 0 then
    Virt.add_chunk(chunks, str, 'LineNr')
    return chunks
  end

  local last_start = 0
  for i, hl in ipairs(highlights) do
    local start = hl.start
    local next_start = highlights[i + 1] and highlights[i + 1].start or #str

    if start > last_start then
      Virt.add_chunk(chunks, str:sub(last_start + 1, start), 'Normal')
    end

    local groups = hl.groups or (hl.group and { hl.group }) or { 'Normal' }
    Virt.add_chunk(chunks, str:sub(start + 1, next_start), groups)
    last_start = next_start
  end

  if last_start < #str then
    Virt.add_chunk(chunks, str:sub(last_start + 1), 'Normal')
  end

  return chunks
end

--- @param win integer
--- @param lnum integer
--- @param width integer
--- @return Gitsigns.VirtTextChunk[]
local function fallback_lno_chunks(win, lnum, width)
  if width <= 0 then
    return {}
  end

  local cursor_lnum = assert(api.nvim_win_get_cursor(win)[1])
  local number = vim.wo[win].number
  local relativenumber = vim.wo[win].relativenumber

  local display_lnum = lnum
  if relativenumber and (not number or lnum ~= cursor_lnum) then
    display_lnum = math.abs(cursor_lnum - lnum)
  end

  local hl = 'LineNr'
  if relativenumber and lnum ~= cursor_lnum then
    hl = lnum < cursor_lnum and 'LineNrAbove' or 'LineNrBelow'
    if vim.fn.hlexists(hl) == 0 then
      hl = 'LineNr'
    end
  end

  local lno_width = math.max(width - 1, 1)
  local current_hybrid = number and relativenumber and lnum == cursor_lnum
  local lno_fmt = current_hybrid and '%-' .. lno_width .. 'd' or '%' .. lno_width .. 'd'
  local lno_str = string.format(lno_fmt, display_lnum)
  if width > lno_width then
    lno_str = lno_str .. ' '
  end
  return chunks_from_statusline(lno_str, { { start = 0, groups = { hl } } })
end

--- @param win integer
--- @return integer
local function lno_width(win)
  local number = vim.wo[win].number
  local relativenumber = vim.wo[win].relativenumber
  if not number and not relativenumber then
    return 0
  end

  local line_count = api.nvim_buf_line_count(api.nvim_win_get_buf(win))

  local digits = 1
  if number then
    digits = math.max(digits, #tostring(line_count))
  end
  if relativenumber then
    local cursor_lnum = assert(api.nvim_win_get_cursor(win)[1])
    digits = math.max(digits, #tostring(math.max(cursor_lnum - 1, line_count - cursor_lnum)))
  end

  return math.max(vim.wo[win].numberwidth - 1, digits) + 1
end

--- @param fmt string
--- @param win integer
--- @param lnum integer
--- @return Gitsigns.VirtTextChunk[]?
local function eval_statusline_chunks(fmt, win, lnum)
  local ok, data = pcall(api.nvim_eval_statusline, fmt, {
    winid = win,
    use_statuscol_lnum = lnum,
    highlights = true,
  })
  if not ok then
    return nil
  end

  return chunks_from_statusline(data.str --[[@as string]], data.highlights or {})
end

--- Build virtual-text chunks matching the window's statuscolumn/number columns.
--- @param win integer
--- @param lnum integer
--- @param opts? {extra_hl?: Gitsigns.HlName|Gitsigns.HlStack}
--- @return Gitsigns.VirtTextChunk[]
local function build_prefix(win, lnum, opts)
  opts = opts or {}
  local width = assert(vim.fn.getwininfo(win)[1]).textoff

  local has_col, statuscol = pcall(function()
    return vim.wo[win].statuscolumn
  end)

  local chunks = {} --- @type Gitsigns.VirtTextChunk[]
  if has_col and statuscol and statuscol ~= '' then
    --- @cast statuscol string
    chunks = eval_statusline_chunks(statuscol, win, lnum) or fallback_lno_chunks(win, lnum, width)
  else
    local number_col_width = math.min(lno_width(win), width)
    local prefix_width = math.max(width - number_col_width, 0)
    if prefix_width > 0 then
      chunks = { { string.rep(' ', prefix_width), 'Normal' } }
    end

    local body_chunks = fallback_lno_chunks(win, lnum, number_col_width)
    vim.list_extend(chunks, body_chunks)
  end

  local extra_hl = opts.extra_hl
  if extra_hl then
    for _, chunk in ipairs(chunks) do
      local groups = {} --- @type Gitsigns.HlStack
      Inspect.append_hl_group(groups, chunk[2])
      Inspect.append_hl_group(groups, extra_hl)
      chunk[2] = Inspect.normalize_hl_groups(groups)
    end
  end

  return chunks
end

--- @param hunk Gitsigns.Hunk.Hunk
--- @return integer row
--- @return boolean above
local function show_deleted_placement(hunk)
  local topdelete = hunk.added.start == 0 and hunk.type == 'delete'
  local row = topdelete and 0 or hunk.added.start - 1
  local above = hunk.type ~= 'delete' or topdelete
  if above and row > 0 then
    return row - 1, false
  end
  return row, above
end

--- @param bufnr integer
local function clear_global_preview(bufnr)
  api.nvim_buf_clear_namespace(bufnr, ns_removed, 0, -1)
end

--- @param entry {ns: integer, bufnr?: integer}
local function clear_win_entry(entry)
  if entry.bufnr and api.nvim_buf_is_valid(entry.bufnr) then
    api.nvim_buf_clear_namespace(entry.bufnr, entry.ns, 0, -1)
  end
  if window_ns_supported then
    api.nvim__ns_set(entry.ns, { wins = {} })
  end
  entry.bufnr = nil
end

--- @param bufnr integer
local function clear_buf_entries(bufnr)
  for winid, entry in pairs(win_ns) do
    if entry.bufnr == bufnr then
      clear_win_entry(entry)
      win_ns[winid] = nil
    end
  end
end

--- @param winid integer
--- @param bufnr integer
--- @return integer
local function get_win_ns(winid, bufnr)
  local entry = win_ns[winid]
  if not entry then
    entry = {
      ns = api.nvim_create_namespace(('gitsigns_removed_win_%d'):format(winid)),
    }
    win_ns[winid] = entry
  elseif entry.bufnr and entry.bufnr ~= bufnr and api.nvim_buf_is_valid(entry.bufnr) then
    api.nvim_buf_clear_namespace(entry.bufnr, entry.ns, 0, -1)
  end

  entry.bufnr = bufnr
  api.nvim__ns_set(entry.ns, { wins = { winid } })
  return entry.ns
end

--- @param lines Gitsigns.CapturedLine[]
--- @param start_lnum integer
--- @param opts? {win?:integer, lno_hl?:boolean}
--- @return Gitsigns.VirtTextChunk[][]
local function render_virt_lines(lines, start_lnum, opts)
  opts = opts or {}

  local prefix --- @type fun(line_index: integer, line: Gitsigns.CapturedLine): Gitsigns.VirtTextChunk[]?
  if opts.lno_hl then
    local win = assert(opts.win)
    prefix = function(line_index)
      return build_prefix(win, start_lnum + line_index - 1, {
        extra_hl = 'GitSignsVirtLnum',
      })
    end
  end

  return Virt.render(lines, {
    pad_width = VIRT_LINE_LEN,
    pad_with_eol_hl = true,
    prefix = prefix,
  })
end

--- @param bufnr integer
--- @param hunk Gitsigns.Hunk.Hunk
--- @param staged boolean?
--- @param opts? {win?:integer, lno_hl?:boolean, word_diff?:boolean}
--- @return Gitsigns.VirtTextChunk[][]
local function build_virt_lines(bufnr, hunk, staged, opts)
  opts = opts or {}
  local source_cache = states[bufnr] and states[bufnr].source_bufs or nil
  local lines = assert(HunkPreview.prepare_removed_hunks(bufnr, { hunk }, staged, {
    line_hl = REMOVED_VIRT_LINE_HL,
    word_diff = opts.word_diff,
    word_diff_hl = REMOVED_INLINE_HL,
    source_cache = source_cache,
  })[1])
  return render_virt_lines(lines, hunk.removed.start, opts)
end

--- @param bufnr integer
--- @param hunks Gitsigns.Hunk.Hunk[]
--- @param captured Gitsigns.CapturedLine[][]
local function render_global_previews(bufnr, hunks, captured)
  clear_global_preview(bufnr)

  for i, hunk in ipairs(hunks) do
    local row, above = show_deleted_placement(hunk)
    api.nvim_buf_set_extmark(bufnr, ns_removed, row, -1, {
      priority = 1000,
      virt_lines = render_virt_lines(assert(captured[i]), hunk.removed.start),
      virt_lines_above = above,
      virt_lines_overflow = VIRT_LINES_OVERFLOW,
    })
  end
end

--- @param source_bufs table<string, Gitsigns.HunkPreview.SourceBuf>?
local function clear_source_bufs(source_bufs)
  if not source_bufs then
    return
  end

  for _, source_buf in pairs(source_bufs) do
    pcall(api.nvim_buf_delete, source_buf.bufnr, { force = true })
  end
end

--- @param bufnr integer
--- @param state {hunks: Gitsigns.Hunk.Hunk[], lines: table<Gitsigns.Hunk.Hunk, Gitsigns.CapturedLine[]>, source_bufs: table<string, Gitsigns.HunkPreview.SourceBuf>, pending?: table<Gitsigns.Hunk.Hunk, true>, scheduled?: boolean}
local function flush_pending_entries(bufnr, state)
  if states[bufnr] ~= state then
    return
  end
  state.scheduled = nil

  local pending = state.pending
  state.pending = nil
  if not pending then
    return
  end

  local missing = {} --- @type Gitsigns.Hunk.Hunk[]
  for _, hunk in ipairs(state.hunks) do
    if pending[hunk] and not state.lines[hunk] then
      missing[#missing + 1] = hunk
    end
  end

  if #missing == 0 then
    return
  end

  local captured = HunkPreview.prepare_removed_hunks(bufnr, missing, false, {
    line_hl = REMOVED_VIRT_LINE_HL,
    word_diff = config.word_diff,
    word_diff_hl = REMOVED_INLINE_HL,
    source_cache = state.source_bufs,
  })

  if states[bufnr] ~= state then
    return
  end

  for i, hunk in ipairs(missing) do
    state.lines[hunk] = captured[i]
  end

  if api.nvim_buf_is_valid(bufnr) then
    util.redraw({ buf = bufnr, range = { 0, api.nvim_buf_line_count(bufnr) } })
  end
end

--- Shared with preview_hunk_inline() so removed lines use the same capture path
--- and highlighting as show_deleted.
--- @param bufnr integer
--- @param ns integer
--- @param hunk Gitsigns.Hunk.Hunk
--- @param staged boolean?
--- @param opts? {win?:integer, lno_hl?:boolean, leftcol?:boolean, word_diff?:boolean}
--- @return integer markid
function M.place_inline_preview_lines(bufnr, ns, hunk, staged, opts)
  opts = opts or {}
  local topdelete = hunk.added.start == 0 and hunk.type == 'delete'
  local row = topdelete and 0 or hunk.added.start - 1
  local above = hunk.type ~= 'delete' or topdelete
  return api.nvim_buf_set_extmark(bufnr, ns, row, -1, {
    virt_lines = build_virt_lines(bufnr, hunk, staged, opts),
    virt_lines_above = above,
    virt_lines_leftcol = opts.leftcol == true,
    virt_lines_overflow = VIRT_LINES_OVERFLOW,
  })
end

--- @param bufnr integer
function M.detach(bufnr)
  local state = states[bufnr]
  states[bufnr] = nil

  clear_global_preview(bufnr)
  clear_buf_entries(bufnr)

  clear_source_bufs(state and state.source_bufs)
end

--- @param bufnr integer
function M.prepare(bufnr)
  local prev = states[bufnr]

  if not config.show_deleted then
    states[bufnr] = nil
    clear_global_preview(bufnr)
    clear_buf_entries(bufnr)
    clear_source_bufs(prev and prev.source_bufs)
    return
  end

  local bcache = cache[bufnr]
  if not bcache or not bcache.hunks or #bcache.hunks == 0 then
    states[bufnr] = nil
    clear_global_preview(bufnr)
    clear_buf_entries(bufnr)
    clear_source_bufs(prev and prev.source_bufs)
    return
  end

  local state = {
    hunks = bcache.hunks,
    lines = {},
    source_bufs = prev and prev.source_bufs or {},
  }
  states[bufnr] = state

  if not window_ns_supported then
    local captured = HunkPreview.prepare_removed_hunks(bufnr, bcache.hunks, false, {
      line_hl = REMOVED_VIRT_LINE_HL,
      word_diff = config.word_diff,
      word_diff_hl = REMOVED_INLINE_HL,
      source_cache = state.source_bufs,
    })

    for i, hunk in ipairs(bcache.hunks) do
      state.lines[hunk] = captured[i]
    end

    render_global_previews(bufnr, bcache.hunks, captured)
  end
end

--- @param winid integer
function M.clear_win(winid)
  local entry = win_ns[winid]
  if not entry then
    return
  end

  clear_win_entry(entry)
  win_ns[winid] = nil
end

--- @param winid integer
--- @param bufnr integer
--- @param topline integer
--- @param botline integer
--- @return boolean
function M.on_win(winid, bufnr, topline, botline)
  if not window_ns_supported then
    return false
  end

  local render_ns = get_win_ns(winid, bufnr)
  local state = states[bufnr]
  if not state or #state.hunks == 0 then
    api.nvim_buf_clear_namespace(bufnr, render_ns, 0, -1)
    return false
  end

  local visible = {} --- @type {row: integer, above: boolean, start_lnum: integer, lines: Gitsigns.CapturedLine[]}[]
  local missing = {} --- @type Gitsigns.Hunk.Hunk[]
  for _, hunk in ipairs(state.hunks) do
    local row, above = show_deleted_placement(hunk)
    if row >= topline - 1 and row < botline then
      local lines = state.lines[hunk]
      if lines then
        visible[#visible + 1] = {
          row = row,
          above = above,
          start_lnum = hunk.removed.start,
          lines = lines,
        }
      else
        missing[#missing + 1] = hunk
      end
    end
  end

  if #missing > 0 then
    state.pending = state.pending or {}
    for _, hunk in ipairs(missing) do
      state.pending[hunk] = true
    end

    if not state.scheduled then
      state.scheduled = true

      -- This path is entered from the decoration provider on_win callback.
      -- Capturing removed lines updates scratch source buffers before capture,
      -- which is not allowed while the buffer is being drawn, so defer the flush.
      vim.schedule(function()
        flush_pending_entries(bufnr, state)
      end)
    end
    return #visible > 0
  end

  api.nvim_buf_clear_namespace(bufnr, render_ns, 0, -1)

  for _, entry in ipairs(visible) do
    api.nvim_buf_set_extmark(bufnr, render_ns, entry.row, -1, {
      priority = 1000,
      virt_lines = render_virt_lines(entry.lines, entry.start_lnum, {
        win = winid,
        lno_hl = true,
      }),
      virt_lines_above = entry.above,
      virt_lines_leftcol = true,
      virt_lines_overflow = VIRT_LINES_OVERFLOW,
    })
  end

  return #visible > 0
end

return M
