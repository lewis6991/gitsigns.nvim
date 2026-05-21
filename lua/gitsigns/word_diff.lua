local api = vim.api

local config = require('gitsigns.config').config
local Hunks = require('gitsigns.hunks')
local manager = require('gitsigns.manager')
local util = require('gitsigns.util')

local M = {}

--- @param ctx Gitsigns.ManagerLine
local function apply_word_diff(ctx)
  if not (config.word_diff and config.diff_opts.internal) then
    return
  end

  -- Don't run on folded lines.
  if vim.fn.foldclosed(ctx.row + 1) ~= -1 then
    return
  end

  local bcache = ctx.bcache
  if not bcache then
    return
  end

  local hunks = bcache.hunks
  if not hunks then
    return
  end

  local line = api.nvim_buf_get_lines(ctx.bufnr, ctx.row, ctx.row + 1, false)[1]
  if not line then
    return
  end

  local lnum = ctx.row + 1

  local hunk = Hunks.find_hunk(lnum, hunks)
  if not hunk then
    return
  end

  if hunk.added.count ~= hunk.removed.count then
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
      -- Make sure region is at least 1 column wide so deletes can be shown.
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
      -- Delete on last column, use virtual text instead.
      opts.virt_text = { { ' ', hl_group } }
      opts.virt_text_pos = 'overlay'
    else
      opts.end_col = ecol
      opts.hl_group = hl_group
    end

    api.nvim_buf_set_extmark(ctx.bufnr, ctx.ns, ctx.row, scol, opts)
    util.redraw({ buf = ctx.bufnr, range = { ctx.row, ctx.row + 1 } })
  end
end

do -- Module-level activation
  manager.on_win(function(ctx)
    if not (config.word_diff and config.diff_opts.internal) then
      return false
    end
    local bcache = ctx.bcache
    return bcache ~= nil and bcache.hunks ~= nil
  end)

  manager.on_line(apply_word_diff)
end

return M
