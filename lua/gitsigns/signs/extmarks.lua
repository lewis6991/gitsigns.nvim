local api = vim.api

local Config = require('gitsigns.config').Config
local config = require('gitsigns.config').config

local setdefault = require('gitsigns.util').setdefault

local B = require('gitsigns.signs.base')

local M = {}

local ExtmarkSign = {}














local placed = {}
local scheduled = {}

setdefault(placed)
setdefault(scheduled)

local ns_em

function M.draw(bufnr, top, bot)
   local to_place = {}
   for i = top, bot do
      if scheduled[bufnr][i] then
         to_place[#to_place + 1] = scheduled[bufnr][i]
         placed[bufnr][i] = scheduled[bufnr][i]
         scheduled[bufnr][i] = nil
      end
   end

   for _, item in ipairs(to_place) do
      api.nvim_buf_set_extmark(bufnr, ns_em, item.row, -1, {
         id = item.id,
         sign_text = item.text,
         priority = item.priority,
         sign_hl_group = item.hl,
         number_hl_group = config.numhl and item.numhl or nil,
         line_hl_group = config.linehl and item.linehl or nil,
      })
   end
end

function M.setup(_redefine)
   ns_em = api.nvim_create_namespace('gitsigns_signs')
end

function M.remove(bufnr, lnum)
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
      api.nvim_buf_clear_namespace(bufnr, ns_em, lnum - 1, lnum)
   end
end

function M.schedule(cfg, bufnr, signs)
   if not cfg.signcolumn and not cfg.numhl and not cfg.linehl then

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
            text = cs.text .. count_char
         end

         scheduled[bufnr][s.lnum] = {
            id = s.lnum,
            text = cfg.signcolumn and text or '',
            row = s.lnum - 1,
            hl = cs.hl,
            numhl = cfg.numhl and cs.numhl,
            linehl = cfg.linehl and cs.linehl,
            priority = cfg.sign_priority,
            type = s.type,
         }
      end
   end
end

function M.add(cfg, bufnr, signs)
   M.schedule(cfg, bufnr, signs)
   for _, s in ipairs(signs) do
      M.draw(bufnr, s.lnum, s.lnum)
   end
end

return M
