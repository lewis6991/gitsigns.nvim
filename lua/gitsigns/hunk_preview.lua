local cache = require('gitsigns.cache').cache
local Capture = require('gitsigns.render.capture')
local Overlay = require('gitsigns.render.overlay')
local config = require('gitsigns.config').config
local util = require('gitsigns.util')

local api = vim.api

local M = {}

--- @class (exact) Gitsigns.HunkPreview.SourceBuf
--- @field bufnr integer
--- @field version any

local NO_NL_TEXT = '\\ No newline at end of file'
local preview_hls = {
  removed = {
    prefix = '-',
    line = 'GitSignsDeletePreview',
  },
  added = {
    prefix = '+',
    line = 'GitSignsAddPreview',
  },
}

--- @param pbufnr integer
--- @param source_buf integer
local function sync_source_buf_options(pbufnr, source_buf)
  vim.bo[pbufnr].filetype = vim.bo[source_buf].filetype
  vim.bo[pbufnr].tabstop = vim.bo[source_buf].tabstop
  vim.bo[pbufnr].syntax = vim.bo[source_buf].syntax
end

local function wait_for_source_render()
  -- Flush one event-loop turn so delayed FileType/syntax/treesitter work on
  -- the scratch source buffer is visible before we capture highlights from it.
  -- This is still synchronous.
  vim.wait(0)
end

--- @param bufnr integer
--- @param lines string[]
--- @return integer source_bufnr
local function create_scratch_source_buf(bufnr, lines)
  local pbufnr = api.nvim_create_buf(false, true)
  vim.bo[pbufnr].bufhidden = 'wipe'
  api.nvim_buf_set_lines(pbufnr, 0, -1, false, lines)
  sync_source_buf_options(pbufnr, bufnr)
  return pbufnr
end

--- @param source_cache? table<string, Gitsigns.HunkPreview.SourceBuf>
--- @param bufnr integer
--- @param lines string[]
--- @param cache_key string
--- @return integer source_bufnr
local function ensure_cached_source_buf(source_cache, bufnr, lines, cache_key)
  if not source_cache then
    return create_scratch_source_buf(bufnr, lines)
  end

  local source_buf = source_cache[cache_key] --- @type Gitsigns.HunkPreview.SourceBuf?
  if source_buf and api.nvim_buf_is_valid(source_buf.bufnr) and source_buf.version ~= lines then
    -- Recreate the cached scratch buffer when the source text changes so any
    -- extmarks/highlights derived from the old contents are discarded.
    pcall(api.nvim_buf_delete, source_buf.bufnr, { force = true })
    source_buf = nil
  end

  if not (source_buf and api.nvim_buf_is_valid(source_buf.bufnr)) then
    local source_bufnr = api.nvim_create_buf(false, true)
    source_buf = {
      bufnr = source_bufnr,
      version = lines,
    }
    api.nvim_buf_set_lines(source_bufnr, 0, -1, false, lines)
    source_cache[cache_key] = source_buf
  end

  local source_bufnr = assert(source_buf).bufnr
  -- Cached scratch sources are reused across captures, so keep them hidden
  -- instead of wiping them when they are no longer displayed.
  vim.bo[source_bufnr].bufhidden = 'hide'
  sync_source_buf_options(source_bufnr, bufnr)
  return source_bufnr
end

--- Prepare a source buffer for capture. This is the only step that waits for
--- delayed FileType/syntax/Treesitter work to settle.
--- @param bufnr integer
--- @param source integer|string[]
--- @param opts? {source_cache?: table<string, Gitsigns.HunkPreview.SourceBuf>, cache_key?: string}
--- @return integer source_bufnr
--- @return fun() cleanup
local function prepare_source(bufnr, source, opts)
  opts = opts or {}

  if type(source) == 'number' then
    return source, function() end
  end

  local lines = source
  if vim.bo[bufnr].fileformat == 'dos' then
    lines = util.strip_cr(lines)
  end

  if opts.source_cache then
    local source_bufnr =
      ensure_cached_source_buf(opts.source_cache, bufnr, lines, assert(opts.cache_key))
    wait_for_source_render()
    return source_bufnr, function() end
  end

  local source_bufnr = create_scratch_source_buf(bufnr, lines)
  wait_for_source_render()
  return source_bufnr,
    function()
      pcall(api.nvim_buf_delete, source_bufnr, { force = true })
    end
end

--- @param bufnr integer
--- @param staged boolean?
--- @param source_cache? table<string, Gitsigns.HunkPreview.SourceBuf>
--- @return integer source_bufnr
--- @return fun() cleanup
function M.prepare_removed_source(bufnr, staged, source_cache)
  local bcache = assert(cache[bufnr])
  local lines = assert(staged and bcache.compare_text_head or bcache.compare_text) --[[@as string[] ]]
  local cache_key = staged and 'removed:staged' or 'removed:unstaged'
  return prepare_source(bufnr, lines, {
    source_cache = source_cache,
    cache_key = cache_key,
  })
end

--- @param lines Gitsigns.CapturedLine[]
--- @param line_hl? Gitsigns.HlName|Gitsigns.HlStack
--- @param word_diff? [integer, string, integer, integer][]
--- @param word_diff_hl Gitsigns.HlName|fun(region_type: string, region: [integer, string, integer, integer]): Gitsigns.HlName?
--- @param line_priority? integer
--- @param word_diff_priority? integer
--- @return Gitsigns.CapturedLine[]
local function apply_capture_layers(
  lines,
  line_hl,
  word_diff,
  word_diff_hl,
  line_priority,
  word_diff_priority
)
  if line_hl then
    Overlay.add_full_line_layer(lines, line_hl, line_priority or 1000)
  end
  if word_diff then
    Overlay.add_word_diff_layers(lines, word_diff, word_diff_hl, word_diff_priority or 1001)
  end

  return lines
end

--- @param removed string[]
--- @param added string[]
--- @param kind 'removed'|'added'
--- @return {[1]:integer, [2]:string, [3]:integer, [4]:integer}[]
local function word_diff_regions(removed, added, kind)
  local removed_regions, added_regions = require('gitsigns.diff_int').run_word_diff(removed, added)
  return kind == 'removed' and removed_regions or added_regions
end

--- @param bufnr integer
--- @param hunk Gitsigns.Hunk.Hunk
--- @return [integer, string, integer, integer][]
local function removed_word_diff_regions(bufnr, hunk)
  local removed = hunk.removed.lines
  local added = hunk.added.lines

  if vim.bo[bufnr].fileformat == 'dos' then
    removed = util.strip_cr(removed)
    added = util.strip_cr(added)
  end

  local removed_regions = require('gitsigns.diff_int').run_word_diff(removed, added)
  return removed_regions
end

--- @param bufnr integer
--- @param source_bufnr integer
--- @param hunks Gitsigns.Hunk.Hunk[]
--- @param opts {line_hl: Gitsigns.HlName|Gitsigns.HlStack, word_diff?: boolean, word_diff_hl: Gitsigns.HlName|fun(region_type: string, region: [integer, string, integer, integer]): Gitsigns.HlName?}
--- @return Gitsigns.CapturedLine[][]
function M.capture_removed_hunks_from_source(bufnr, source_bufnr, hunks, opts)
  local ret = {} --- @type Gitsigns.CapturedLine[][]
  for i, hunk in ipairs(hunks) do
    ret[i] = apply_capture_layers(
      Capture.capture_node(source_bufnr, hunk.removed),
      opts.line_hl,
      opts.word_diff and removed_word_diff_regions(bufnr, hunk) or nil,
      opts.word_diff_hl
    )
  end
  return ret
end

--- Prepare the removed source as needed and return captured removed lines.
--- May allocate scratch buffers and wait for source rendering before capture.
--- @param bufnr integer
--- @param hunks Gitsigns.Hunk.Hunk[]
--- @param staged boolean?
--- @param opts {source_cache?: table<string, Gitsigns.HunkPreview.SourceBuf>, line_hl: Gitsigns.HlName|Gitsigns.HlStack, word_diff?: boolean, word_diff_hl: Gitsigns.HlName|fun(region_type: string, region: [integer, string, integer, integer]): Gitsigns.HlName?}
--- @return Gitsigns.CapturedLine[][]
function M.prepare_removed_hunks(bufnr, hunks, staged, opts)
  local source_bufnr, cleanup = M.prepare_removed_source(bufnr, staged, opts.source_cache)
  local captured = M.capture_removed_hunks_from_source(bufnr, source_bufnr, hunks, {
    line_hl = opts.line_hl,
    word_diff = opts.word_diff ~= false,
    word_diff_hl = opts.word_diff_hl,
  })
  cleanup()
  return captured
end

--- @param layer Gitsigns.RenderLayer
--- @param text_len integer
--- @return Gitsigns.HlMark?
local function layer_to_mark(layer, text_len)
  local start_col = math.max(layer.start_col, 0)
  local end_col = math.max(layer.end_col, start_col)

  if end_col <= start_col then
    return
  end

  -- Popup line highlights are added as 0 .. #text + 1 so the buffer extmark
  -- can span to the start of the next row and cover the visible EOL padding.
  local extends_to_eol = start_col == 0 and end_col > text_len

  return {
    hl_group = layer.hl_group,
    start_row = 0,
    start_col = start_col,
    end_row = extends_to_eol and 1 or 0,
    end_col = extends_to_eol and 0 or math.min(end_col, text_len),
    priority = layer.priority,
  }
end

--- @param lines Gitsigns.CapturedLine[]
--- @param opts? {no_nl_at_eof?: boolean}
--- @return Gitsigns.LineSpec[]
local function render_popup_lines(lines, opts)
  opts = opts or {}

  local ret = {} --- @type Gitsigns.LineSpec[]
  for i, line in ipairs(lines) do
    local marks = {} --- @type Gitsigns.HlMark[]
    for _, layer in ipairs(line.layers or {}) do
      marks[#marks + 1] = layer_to_mark(layer, #line.text)
    end
    ret[i] = { { line.text, marks } }
  end

  if opts.no_nl_at_eof then
    ret[#ret + 1] = {
      {
        NO_NL_TEXT,
        {
          {
            start_row = 0,
            end_row = 1,
            hl_group = 'GitSignsNoEOLPreview',
          },
        },
      },
    }
  end

  return ret
end

--- @param _bufnr integer
--- @param kind 'removed'|'added'
--- @param source_bufnr integer
--- @param node Gitsigns.Hunk.Node
--- @param removed string[]
--- @param added string[]
--- @return Gitsigns.CapturedLine[]
local function capture_popup_lines(_bufnr, kind, source_bufnr, node, removed, added)
  local captured = apply_capture_layers(
    Capture.capture_node(source_bufnr, node),
    nil,
    config.diff_opts.internal and word_diff_regions(removed, added, kind) or nil,
    function(region_type)
      return kind == 'removed' and 'GitSignsDeleteInline'
        or region_type == 'add' and 'GitSignsAddInline'
        or region_type == 'change' and 'GitSignsChangeInline'
        or 'GitSignsDeleteInline'
    end
  )

  local prefix = preview_hls[kind].prefix
  local prefix_len = #prefix
  local line_hl = preview_hls[kind].line
  for _, line in ipairs(captured) do
    if prefix_len > 0 then
      for _, layer in ipairs(line.layers) do
        layer.start_col = layer.start_col + prefix_len
        layer.end_col = layer.end_col + prefix_len
      end
      line.text = prefix .. line.text
    end

    Overlay.add_layer(line, 0, #line.text + 1, line_hl, 1000)
  end

  return captured
end

--- Return popup lines for a hunk.
--- May allocate scratch buffers and wait for source rendering before capture.
--- @param bufnr integer
--- @param hunk Gitsigns.Hunk.Hunk
--- @param removed_source integer|string[]
--- @param added_source integer|string[]
--- @param added_node Gitsigns.Hunk.Node
--- @return Gitsigns.LineSpec[]
function M.linespec_for_hunk(bufnr, hunk, removed_source, added_source, added_node)
  local removed_source_bufnr, cleanup_removed = prepare_source(bufnr, removed_source)
  local added_source_bufnr, cleanup_added = prepare_source(bufnr, added_source)

  local removed = hunk.removed.lines
  local added = hunk.added.lines

  if vim.bo[bufnr].fileformat == 'dos' then
    removed = util.strip_cr(removed)
    added = util.strip_cr(added)
  end

  local ret = {} --- @type Gitsigns.LineSpec[]
  if hunk.removed.count > 0 then
    vim.list_extend(
      ret,
      render_popup_lines(
        capture_popup_lines(bufnr, 'removed', removed_source_bufnr, hunk.removed, removed, added),
        {
          no_nl_at_eof = config.diff_opts.internal
            and hunk.removed.no_nl_at_eof
            and not hunk.added.no_nl_at_eof,
        }
      )
    )
  end

  if added_node.count > 0 then
    vim.list_extend(
      ret,
      render_popup_lines(
        capture_popup_lines(bufnr, 'added', added_source_bufnr, added_node, removed, added),
        {
          no_nl_at_eof = config.diff_opts.internal
            and added_node.no_nl_at_eof
            and not hunk.removed.no_nl_at_eof,
        }
      )
    )
  end

  cleanup_added()
  cleanup_removed()

  return ret
end

return M
