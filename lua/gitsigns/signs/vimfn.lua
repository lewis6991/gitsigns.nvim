local fn = vim.fn

local SignsConfig = require('gitsigns.config').Config.SignsConfig
local config = require('gitsigns.config').config

local emptytable = require('gitsigns.util').emptytable

local B = require('gitsigns.signs.base')

local M = {}









local function capitalise_word(x)
   return x:sub(1, 1):upper() .. x:sub(2)
end

local function get_sign_name(obj, stype)
   local cache = obj.sign_name_cache
   if not cache[stype] then
      cache[stype] = string.format(
      '%s%s', 'GitSigns', capitalise_word(stype))
   end

   return cache[stype]
end

local function sign_get(obj, name)
   if not obj.sign_define_cache[name] then
      local s = fn.sign_getdefined(name)
      if not vim.tbl_isempty(s) then
         obj.sign_define_cache[name] = s
      end
   end
   return obj.sign_define_cache[name]
end

local function define_sign(obj, name, opts, redefine)
   if redefine then
      obj.sign_define_cache[name] = nil
      fn.sign_undefine(name)
      fn.sign_define(name, opts)
   elseif not sign_get(obj, name) then
      fn.sign_define(name, opts)
   end
end

local function define_signs(obj, redefine)

   for stype, cs in pairs(obj.config) do
      define_sign(obj, get_sign_name(obj, stype), {
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
   self.placed = emptytable()
   self.sign_name_cache = {}
   self.sign_define_cache = {}

   define_signs(self, false)

   return self
end

function M:on_lines(_, _, _, _)
end

function M:remove(bufnr, start_lnum, end_lnum)
   end_lnum = end_lnum or start_lnum

   if start_lnum then
      for lnum = start_lnum, end_lnum do
         self.placed[bufnr][lnum] = nil
         fn.sign_unplace(self.group, { buffer = bufnr, id = lnum })
      end
   else
      self.placed[bufnr] = nil
      fn.sign_unplace(self.group, { buffer = bufnr })
   end
end

function M:add(bufnr, signs)
   if not config.signcolumn and not config.numhl and not config.linehl then

      return
   end

   local to_place = {}

   local cfg = self.config
   for _, s in ipairs(signs) do
      local sign_name = get_sign_name(self, s.type)

      local cs = cfg[s.type]
      if config.signcolumn and cs.show_count and s.count then
         local count = s.count
         local cc = config.count_chars
         local count_suffix = cc[count] and tostring(count) or (cc['+'] and 'Plus') or ''
         local count_char = cc[count] or cc['+'] or ''
         sign_name = sign_name .. count_suffix
         define_sign(self, sign_name, {
            texthl = cs.hl,
            text = config.signcolumn and cs.text .. count_char or '',
            numhl = config.numhl and cs.numhl,
            linehl = config.linehl and cs.linehl,
         })
      end

      if not self.placed[bufnr][s.lnum] then
         local sign = {
            id = s.lnum,
            group = self.group,
            name = sign_name,
            buffer = bufnr,
            lnum = s.lnum,
            priority = config.sign_priority,
         }
         self.placed[bufnr][s.lnum] = sign
         to_place[#to_place + 1] = sign
      end
   end

   if #to_place > 0 then
      fn.sign_placelist(to_place)
   end
end

function M:contains(bufnr, start, last)
   for i = start + 1, last + 1 do
      if self.placed[bufnr][i] then
         return true
      end
   end
   return false
end

function M:reset()
   self.placed = emptytable()
   fn.sign_unplace(self.group)
   define_signs(self, true)
end

return M
