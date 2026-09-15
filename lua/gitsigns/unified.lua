local async = require('gitsigns.async')
local HunkPreview = require('gitsigns.hunk_preview')
local DeletedPreview = require('gitsigns.deleted_preview')
local DiffBuffers = require('gitsigns.diff_buffers')
local util = require('gitsigns.util')

local api = vim.api
local M = {}

--- @class Gitsigns.UnifiedPreview
--- @field hunk Gitsigns.Hunk.Hunk
--- @field lines Gitsigns.CapturedLine[]
--- @field id? integer

--- @class Gitsigns.UnifiedView
--- @field buf integer
--- @field base integer
--- @field ns integer
--- @field hunks Gitsigns.Hunk.Hunk[]?
--- @field previews Gitsigns.UnifiedPreview[]?
--- @field numberwidth? integer Original width, if widened for base line numbers.
--- @field min_numberwidth? integer Last width applied by this view.

local views = {} --- @type table<integer, Gitsigns.UnifiedView>
local attached = {} --- @type table<integer, true>

--- @param win integer
--- @param keep_base? integer A base buffer about to be reused by another layout.
function M.close(win, keep_base)
  local view = views[win]
  if not view then
    return
  end
  views[win] = nil
  -- Restore only the width we set, preserving later user changes.
  if
    view.numberwidth
    and api.nvim_win_is_valid(win)
    and vim.wo[win].numberwidth == view.min_numberwidth
  then
    vim.wo[win].numberwidth = view.numberwidth
  end
  if api.nvim_buf_is_valid(view.buf) then
    api.nvim_buf_clear_namespace(view.buf, view.ns, 0, -1)
  end

  DiffBuffers.release(view.base, view.base == keep_base)
end

--- @param win? integer
--- @return Gitsigns.UnifiedView?
function M.get_view(win)
  win = win or api.nvim_get_current_win()
  local view = views[win]
  if view and api.nvim_win_get_buf(win) == view.buf then
    return view
  end
end

--- @param buf integer
--- @param base? integer Limit the check to views with this comparison buffer.
--- @return boolean
function M.is_active(buf, base)
  for _, view in pairs(views) do
    if view.buf == buf and (not base or view.base == base) then
      return true
    end
  end
  return false
end

--- Virtual lines above the first buffer line need filler space in the viewport.
--- @param win? integer
function M.reveal(win)
  win = win or api.nvim_get_current_win()
  local view = M.get_view(win)
  local hunks = view and view.hunks
  local first = hunks and hunks[1]
  if first and first.added.start <= 1 and first.removed.count > 0 then
    api.nvim_win_call(win, function()
      -- Revealing a large deletion can push another cursor row out of the window.
      if api.nvim_win_get_cursor(win)[1] == 1 and vim.fn.line('w0') == 1 then
        vim.cmd.normal({ first.removed.count .. '\25', bang = true })
      end
    end)
  end
end

--- Rebuild the gutter during redraw: signs can arrive after the diff is ready.
--- Keep the captured content and extmarks, just refresh the visible previews.
--- @param win integer
--- @param view Gitsigns.UnifiedView
--- @param top integer
--- @param bot integer
local function render_previews(win, view, top, bot)
  for _, preview in ipairs(view.previews or {}) do
    local row = math.max(preview.hunk.added.start - 1, 0)
    if row >= top - 1 and row < bot then
      preview.id =
        DeletedPreview.place_inline_preview_lines(view.buf, view.ns, preview.hunk, false, {
          id = preview.id,
          win = win,
          lno_hl = true,
          absolute_lnum = true,
          leftcol = true,
          lines = preview.lines,
        })
    end
  end
end

--- Recompute against the displayed pair, independently of the buffer's Git base.
--- That base may be the index even when the panel compares two historical paths.
--- @async
--- @param win integer
local update = require('gitsigns.debounce').throttle_async(
  { hash = 1, schedule = true },
  function(win)
    local view = views[win]
    if not view then
      return
    end
    if not api.nvim_win_is_valid(win) or api.nvim_win_get_buf(win) ~= view.buf then
      M.close(win)
      return
    end

    local tick = api.nvim_buf_get_changedtick(view.buf)
    local base_tick = api.nvim_buf_get_changedtick(view.base)
    local hunks = require('gitsigns.diff')(util.buf_lines(view.base), util.buf_lines(view.buf))
    async.schedule()
    if
      views[win] ~= view
      or not api.nvim_buf_is_valid(view.buf)
      or not api.nvim_buf_is_valid(view.base)
      or api.nvim_buf_get_changedtick(view.buf) ~= tick
      or api.nvim_buf_get_changedtick(view.base) ~= base_tick
    then
      return
    end

    -- Nvim sizes its number column from the current buffer, but deleted lines
    -- can have larger base-revision numbers. Reserve space for both sides.
    local numberwidth = vim.wo[win].numberwidth
    local min_numberwidth = #tostring(api.nvim_buf_line_count(view.base)) + 1
    if numberwidth < min_numberwidth then
      if numberwidth ~= view.min_numberwidth then
        view.numberwidth = numberwidth
      end
      view.min_numberwidth = min_numberwidth
      vim.wo[win].numberwidth = min_numberwidth
    end

    local lines = HunkPreview.capture_removed_hunks_from_source(view.buf, view.base, hunks, {
      line_hl = 'GitSignsDeleteVirtLn',
      word_diff = true,
      word_diff_hl = 'GitSignsDeleteVirtLnInLine',
    })
    view.hunks = hunks
    view.previews = {}
    api.nvim_buf_clear_namespace(view.buf, view.ns, 0, -1)
    for i, hunk in ipairs(hunks) do
      HunkPreview.highlight_added_hunk(view.buf, view.ns, hunk)
      if hunk.removed.count > 0 then
        view.previews[#view.previews + 1] = { hunk = hunk, lines = assert(lines[i]) }
      end
    end
    render_previews(win, view, 0, api.nvim_buf_line_count(view.buf))
    M.reveal(win)
  end
)

--- Watch both sides, including scratch buffers that are not attached to Gitsigns.
--- @param buf integer
local function watch(buf)
  if attached[buf] then
    return
  end
  attached[buf] = true
  local function refresh()
    local used = false
    for win, view in pairs(views) do
      if view.buf == buf or view.base == buf then
        used = true
        -- The old hunk positions are stale until the asynchronous diff finishes.
        view.previews = nil
        vim.schedule(function()
          async.run(update, win):raise_on_error()
        end)
      end
    end
    if not used then
      attached[buf] = nil
      return true
    end
  end
  api.nvim_buf_attach(buf, false, {
    on_lines = refresh,
    on_reload = refresh,
    on_detach = function()
      attached[buf] = nil
      vim.schedule(function()
        for win, view in pairs(views) do
          if view.buf == buf or view.base == buf then
            M.close(win)
          end
        end
      end)
    end,
  })
end

--- Show the current file with the base's removed lines inline.
--- Keep the base alive while hidden, including when multiple panels share it.
--- @async
--- @param win integer
--- @param base_buf integer
--- @param created? boolean
--- @param loaded? boolean
function M.show(win, base_buf, created, loaded)
  DiffBuffers.retain(base_buf, created, loaded)
  M.close(win)

  local buf = api.nvim_win_get_buf(win)
  local ns = api.nvim_create_namespace('gitsigns_unified_' .. win)
  api.nvim__ns_set(ns, { wins = { win } })
  views[win] = { buf = buf, base = base_buf, ns = ns }
  require('gitsigns.actions.preview').clear_preview_inline(buf)
  watch(buf)
  watch(base_buf)
  update(win)
end

require('gitsigns.manager').on_win(function(ctx)
  local view = views[ctx.winid]
  if view and view.buf == ctx.bufnr and view.previews and #view.previews > 0 then
    local width = assert(vim.fn.getwininfo(ctx.winid)[1]).textoff
    render_previews(ctx.winid, view, ctx.topline, ctx.botline)

    -- Nvim adjusts 'signcolumn=auto' after on_win. Redraw again if that changed
    -- the width used for these prefixes, even when no further input arrives.
    vim.schedule(function()
      if
        views[ctx.winid] == view
        and api.nvim_win_is_valid(ctx.winid)
        and api.nvim_win_get_buf(ctx.winid) == view.buf
        and assert(vim.fn.getwininfo(ctx.winid)[1]).textoff ~= width
      then
        api.nvim__redraw({ win = ctx.winid, valid = false })
      end
    end)
  end
  return false
end)

api.nvim_create_autocmd('WinClosed', {
  group = api.nvim_create_augroup('gitsigns.unified', {}),
  callback = function(args)
    M.close(assert(tonumber(args.match)) --[[@as integer]])
  end,
})

api.nvim_create_autocmd('BufWinLeave', {
  group = 'gitsigns.unified',
  callback = function(args)
    local win = api.nvim_get_current_win()
    if views[win] and views[win].buf == args.buf then
      M.close(win)
    end
  end,
})

return M
