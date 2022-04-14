local api = vim.api

local Config = require('gitsigns.config').Config
local config = require('gitsigns.config').config

local setdefault = require('gitsigns.util').setdefault

local B = require('gitsigns.signs.base')

local M: B = {}

local record ExtmarkSign
  id: integer
  row: integer
  text: string
  hl: string
  linehl: string
  numhl: string
  priority: integer
  type: M.SignType
end

-- API which keeps track of which signs have already been placed in the buffer.
-- This allows us to:
--   - efficiently query placed signs.
--   - skip adding a sign if it has already been placed.
local placed: {integer:{integer:ExtmarkSign}} = {}
local scheduled: {integer:{integer:ExtmarkSign}} = {}

setdefault(placed)
setdefault(scheduled)

local ns_em: integer

function M.draw(bufnr: integer, top: integer, bot: integer): boolean
  local to_place = {}
  for i = top, bot do
    if scheduled[bufnr][i] then
      to_place[#to_place+1] = scheduled[bufnr][i]
      placed[bufnr][i] = scheduled[bufnr][i]
      scheduled[bufnr][i]= nil
    end
  end

  for _, item in ipairs(to_place) do
    api.nvim_buf_set_extmark(bufnr, ns_em, item.row, -1, {
      id              = item.id,
      sign_text       = item.text,
      priority        = item.priority,
      sign_hl_group   = item.hl,
      number_hl_group = config.numhl and item.numhl or nil,
      line_hl_group   = config.linehl and item.linehl or nil,
    })
  end
end

function M.setup(_redefine: boolean)
  ns_em = api.nvim_create_namespace('gitsigns_signs')
end

function M.remove(bufnr: integer, lnum: integer)
  if lnum then
    placed[bufnr][lnum] = nil
    scheduled[bufnr][lnum] = nil
  else
    placed[bufnr] = nil
    scheduled[bufnr] = nil
  end

  if not lnum then
    api.nvim_buf_clear_namespace(bufnr, ns_em, 0, -1)
  else
    api.nvim_buf_clear_namespace(bufnr, ns_em, lnum-1, lnum)
  end
end

function M.schedule(cfg: Config, bufnr: integer, signs: {M.Sign})
  if not cfg.signcolumn and not cfg.numhl and not cfg.linehl then
    -- Don't place signs if it won't show anything
    return
  end

  for _, s in ipairs(signs) do
    if not placed[bufnr][s.lnum] then
      local cs = cfg.signs[s.type]
      local text = cs.text
      if cfg.signcolumn and cs.show_count and s.count then
        local count = s.count
        local cc = cfg.count_chars
        local count_char = cc[count] or cc['+'] or ''
        text = cs.text..count_char
      end

      scheduled[bufnr][s.lnum] = {
        id       = s.lnum,
        text     = cfg.signcolumn and text or '',
        row      = s.lnum-1,
        hl       = cs.hl,
        numhl    = cfg.numhl  and cs.numhl,
        linehl   = cfg.linehl and cs.linehl,
        priority = cfg.sign_priority,
        type     = s.type
      }
    end
  end
end

function M.add(cfg: Config, bufnr: integer, signs: {M.Sign})
  M.schedule(cfg, bufnr, signs)
  for _, s in ipairs(signs) do
    M.draw(bufnr, s.lnum, s.lnum)
  end
end

function M.need_redraw(bufnr: integer, start: integer, last: integer): boolean
  -- Use nvim_buf_get_extmarks as that should be quicker than scanning 'placed'
  local marks = api.nvim_buf_get_extmarks(bufnr, ns_em, {start, 0}, {last+1, 0}, {limit=1})
  return #marks > 0
end

return M
