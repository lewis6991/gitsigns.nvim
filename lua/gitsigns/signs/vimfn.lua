local fn = vim.fn

local SignsConfig = require('gitsigns.config').Config.SignsConfig
local config = require('gitsigns.config').config

local setdefault = require('gitsigns.util').setdefault

local B = require('gitsigns.signs.base')

local M = {}

local SignName = {}







local sign_map = {
   add = "GitSignsAdd",
   delete = "GitSignsDelete",
   change = "GitSignsChange",
   topdelete = "GitSignsTopDelete",
   changedelete = "GitSignsChangeDelete",
}












function M.draw(self, bufnr, top, bot)
   local to_place = {}
   for i = top, bot do
      if self.scheduled[bufnr][i] then
         to_place[#to_place + 1] = self.scheduled[bufnr][i]
         self.placed[bufnr][i] = self.scheduled[bufnr][i]
         self.scheduled[bufnr][i] = nil
      end
   end
   if to_place[1] then
      fn.sign_placelist(to_place)
   end
end

local sign_define_cache = {}

local function sign_get(name)
   if not sign_define_cache[name] then
      local s = fn.sign_getdefined(name)
      if not vim.tbl_isempty(s) then
         sign_define_cache[name] = s
      end
   end
   return sign_define_cache[name]
end


local function define_sign(name, opts, redefine)
   if redefine then
      sign_define_cache[name] = nil
      fn.sign_undefine(name)
      fn.sign_define(name, opts)
   elseif not sign_get(name) then
      fn.sign_define(name, opts)
   end
end

local function define_signs(obj, redefine)

   for t, name in pairs(sign_map) do
      local cs = obj.config[t]
      define_sign(name, {
         texthl = cs.hl,
         text = config.signcolumn and cs.text or nil,
         numhl = config.numhl and cs.numhl,
         linehl = config.linehl and cs.linehl,
      }, redefine)
   end
end

local group_base = 'gitsigns_vimfn_signs_'

function M.new(cfg, name)
   local self = setmetatable({}, { __index = M })
   self.group = group_base .. (name or '')
   self.config = cfg
   self.placed = {}
   self.scheduled = {}

   setdefault(self.placed)
   setdefault(self.scheduled)

   define_signs(self, false)

   return self
end

function M.remove(self, bufnr, start_lnum, end_lnum)
   end_lnum = end_lnum or start_lnum

   if start_lnum then
      for lnum = start_lnum, end_lnum do
         self.placed[bufnr][lnum] = nil
         self.scheduled[bufnr][lnum] = nil
         fn.sign_unplace(self.group, { buffer = bufnr, id = lnum })
      end
   else
      self.placed[bufnr] = nil
      self.scheduled[bufnr] = nil
      fn.sign_unplace(self.group, { buffer = bufnr })
   end
end

function M.schedule(self, bufnr, signs)
   if not config.signcolumn and not config.numhl and not config.linehl then

      return
   end

   local cfg = self.config
   for _, s in ipairs(signs) do
      local stype = sign_map[s.type]

      local cs = cfg[s.type]
      if config.signcolumn and cs.show_count and s.count then
         local count = s.count
         local cc = config.count_chars
         local count_suffix = cc[count] and tostring(count) or (cc['+'] and 'Plus') or ''
         local count_char = cc[count] or cc['+'] or ''
         stype = stype .. count_suffix
         define_sign(stype, {
            texthl = cs.hl,
            text = config.signcolumn and cs.text .. count_char or '',
            numhl = config.numhl and cs.numhl,
            linehl = config.linehl and cs.linehl,
         })
      end

      if not self.placed[bufnr][s.lnum] then
         self.scheduled[bufnr][s.lnum] = {
            id = s.lnum,
            group = self.group,
            name = stype,
            buffer = bufnr,
            lnum = s.lnum,
            priority = config.sign_priority,
         }
      end
   end
end

function M.add(self, bufnr, signs)
   self:schedule(bufnr, signs)
   for _, s in ipairs(signs) do
      self:draw(bufnr, s.lnum, s.lnum)
   end
end

function M.need_redraw(self, bufnr, start, last)
   for i = start + 1, last + 1 do
      if self.placed[bufnr][i] then
         return true
      end
   end
   return false
end

function M.reset(self)
   self.placed = {}
   self.scheduled = {}
   setdefault(self.placed)
   setdefault(self.scheduled)
   fn.sign_unplace(self.group)
   define_signs(self, true)
end

return M
