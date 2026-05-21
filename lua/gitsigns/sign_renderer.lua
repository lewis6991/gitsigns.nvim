local api = vim.api

local Config = require('gitsigns.config')
local config = Config.config
local Hunks = require('gitsigns.hunks')
local manager = require('gitsigns.manager')
local Signs = require('gitsigns.signs')

local signs_normal = Signs.new()
local signs_staged = Signs.new(true)

local M = {}

local statuscolumn_active = false

--- @param bufnr? integer
--- @param top? integer
--- @param bot? integer
local function redraw_statuscol(bufnr, top, bot)
  if statuscolumn_active then
    api.nvim__redraw({
      buf = bufnr,
      range = (top and bot) and { top, bot } or nil,
      statuscolumn = true,
    })
  end
end

--- @param bufnr? integer
--- @param lnum? integer
--- @return string
function M.statuscolumn(bufnr, lnum)
  if bufnr == nil or bufnr == 0 then
    bufnr = api.nvim_get_current_buf()
  end
  lnum = lnum or vim.v.lnum
  statuscolumn_active = true

  if not config._statuscolumn then
    config.signcolumn = false
    config._statuscolumn = true
  end

  local res = {} --- @type string[]
  local res_len = 0
  for _, signs in ipairs({ signs_normal, signs_staged }) do
    local buf_signs = signs.signs[bufnr]
    if buf_signs and next(buf_signs) then
      local marks = api.nvim_buf_get_extmarks(
        bufnr,
        signs.ns,
        { lnum - 1, 0 },
        { lnum - 1, -1 },
        {}
      )
      for _, mark in ipairs(marks) do
        local id = mark[1]
        local s = buf_signs[id]
        if s then
          vim.list_extend(res, { '%#' .. s[2] .. '#', s[1], '%*' })
          --- @diagnostic disable-next-line: missing-parameter
          res_len = res_len + vim.str_utfindex(s[1])
        end
      end
    end
  end
  local pad = math.max(0, 2 - res_len)
  return table.concat(res) .. string.rep(' ', pad)
end

--- @param bufnr integer
--- @param signs Gitsigns.Signs
--- @param hunks? Gitsigns.Hunk.Hunk[]
--- @param top integer
--- @param bot integer
--- @param clear? boolean
--- @param untracked boolean
--- @param filter? fun(line: integer):boolean
local function apply_hunk_signs(bufnr, signs, hunks, top, bot, clear, untracked, filter)
  if clear then
    signs:remove(bufnr)
  end

  hunks = hunks or {}

  for i, hunk in ipairs(hunks) do
    --- @type Gitsigns.Hunk.Hunk?, Gitsigns.Hunk.Hunk?
    local prev_hunk, next_hunk = hunks[i - 1], hunks[i + 1]

    -- To stop the sign column width changing too much, if there are signs to be
    -- added but none of them are visible in the window, then make sure to add at
    -- least one sign. Only do this on the first call after an update, when all
    -- signs have been cleared.
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
--- @param bcache Gitsigns.CacheEntry
--- @param top integer
--- @param bot integer
--- @param clear? boolean
local function apply_win(bufnr, bcache, top, bot, clear)
  local untracked = bcache.git_obj.object_name == nil
  apply_hunk_signs(bufnr, signs_normal, bcache.hunks, top, bot, clear, untracked)
  apply_hunk_signs(bufnr, signs_staged, bcache.hunks_staged, top, bot, clear, false, function(lnum)
    return not signs_normal:contains(bufnr, lnum)
  end)
  if clear then
    redraw_statuscol(bufnr, top, bot)
  end
end

function M.reset()
  signs_normal:reset()
  signs_staged:reset()
end

do -- Module-level activation
  manager.on_lines(function(ctx)
    signs_normal:on_lines(ctx.bufnr, ctx.first, ctx.last_orig, ctx.last_new)
    signs_staged:on_lines(ctx.bufnr, ctx.first, ctx.last_orig, ctx.last_new)

    -- Signs in changed regions get invalidated so we need to force a redraw if
    -- any signs get removed.
    if ctx.bcache.hunks and signs_normal:contains(ctx.bufnr, ctx.first, ctx.last_new) then
      -- Force a sign redraw on the next update (fixes #521)
      ctx.bcache.force_next_update = true
    end

    if ctx.bcache.hunks_staged and signs_staged:contains(ctx.bufnr, ctx.first, ctx.last_new) then
      -- Force a sign redraw on the next update (fixes #521)
      ctx.bcache.force_next_update = true
    end
  end)

  manager.on_update(function(ctx)
    apply_win(ctx.bufnr, ctx.bcache, vim.fn.line('w0'), vim.fn.line('w$'), true)
  end)

  manager.on_detach(function(bufnr, keep_signs)
    if keep_signs then
      return
    end

    signs_normal:remove(bufnr)
    signs_staged:remove(bufnr)
    redraw_statuscol(bufnr)
  end)

  manager.on_win(function(ctx)
    if ctx.bcache and ctx.bcache.hunks then
      apply_win(ctx.bufnr, ctx.bcache, ctx.topline + 1, ctx.botline + 1)
    end
    return false
  end)

  Config.subscribe({ 'signcolumn', 'numhl', 'linehl', 'show_deleted', 'word_diff' }, function()
    M.reset()
  end)
end

return M
