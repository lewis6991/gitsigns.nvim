local api = vim.api

local SignsConfig = require('gitsigns.config').Config.SignsConfig
local config = require('gitsigns.config').config
local nvim = require('gitsigns.nvim')

local B = require('gitsigns.signs.base')

local M = {}



local function attach(obj, bufnr)
   bufnr = bufnr or api.nvim_get_current_buf()
   api.nvim_buf_attach(bufnr, false, {
      on_lines = function(_, buf, _, _, last_orig, last_new)
         if last_orig > last_new then
            obj:remove(buf, last_new + 1, last_orig)
         end
      end,
   })
end

local group_base = 'gitsigns_extmark_signs_'

function M.new(cfg, name)
   local self = setmetatable({}, { __index = M })
   self.config = cfg
   self.group = group_base .. (name or '')
   self.ns = api.nvim_create_namespace(self.group)

   nvim.augroup(self.group)
   nvim.autocmd('BufRead', {
      group = self.group,
      callback = vim.schedule_wrap(function()
         attach(self)
      end),
   })


   for _, buf in ipairs(api.nvim_list_bufs()) do
      if api.nvim_buf_is_loaded(buf) and api.nvim_buf_get_name(buf) ~= '' then
         attach(self, buf)
      end
   end

   return self
end

function M.draw(_self, _bufnr, _top, _bot)
end

function M.remove(self, bufnr, start_lnum, end_lnum)
   if start_lnum then
      api.nvim_buf_clear_namespace(bufnr, self.ns, start_lnum - 1, end_lnum or start_lnum)
   else
      api.nvim_buf_clear_namespace(bufnr, self.ns, 0, -1)
   end
end

local function placed(self, bufnr, start, last)
   local marks = api.nvim_buf_get_extmarks(
   bufnr, self.ns,
   { start - 1, 0 },
   { last or start, 0 },
   { limit = 1 })

   return #marks > 0
end

function M.schedule(self, bufnr, signs)
   if not config.signcolumn and not config.numhl and not config.linehl then

      return
   end

   local cfg = self.config

   for _, s in ipairs(signs) do
      if not placed(self, bufnr, s.lnum) then
         local cs = cfg[s.type]
         local text = cs.text
         if config.signcolumn and cs.show_count and s.count then
            local count = s.count
            local cc = config.count_chars
            local count_char = cc[count] or cc['+'] or ''
            text = cs.text .. count_char
         end

         api.nvim_buf_set_extmark(bufnr, self.ns, s.lnum - 1, -1, {
            id = s.lnum,
            sign_text = config.signcolumn and text or '',
            priority = config.sign_priority,
            sign_hl_group = cs.hl,
            number_hl_group = config.numhl and cs.numhl or nil,
            line_hl_group = config.linehl and cs.linehl or nil,
         })
      end
   end
end

function M.add(self, bufnr, signs)
   self:schedule(bufnr, signs)
end

function M.need_redraw(self, bufnr, start, last)
   return placed(self, bufnr, start, last)
end

function M.reset(self)
   for _, buf in ipairs(api.nvim_list_bufs()) do
      self:remove(buf)
   end
end

return M
