local fn = vim.fn

local Config = require('gitsigns.config').Config

local M = {Sign = {}, }

























M.sign_map = {
   add = "GitSignsAdd",
   delete = "GitSignsDelete",
   change = "GitSignsChange",
   topdelete = "GitSignsTopDelete",
   changedelete = "GitSignsChangeDelete",
}

local sign_group = 'gitsigns_ns'










local placed = {}
local scheduled = {}

local function setdefault(tbl)
   setmetatable(tbl, {
      __index = function(t, k)
         t[k] = {}
         return t[k]
      end,
   })
end

setdefault(placed)
setdefault(scheduled)

local sign_define_cache = {}


function M.draw(bufnr, top, bot)
   local to_place = {}
   for i = top, bot do
      if scheduled[bufnr][i] then
         to_place[#to_place + 1] = scheduled[bufnr][i]
         placed[bufnr][i] = scheduled[bufnr][i]
         scheduled[bufnr][i] = nil
      end
   end
   if to_place[1] then
      fn.sign_placelist(to_place)
   end
end

local function sign_get(name)

   if not sign_define_cache[name] then
      local s = fn.sign_getdefined(name)
      if not vim.tbl_isempty(s) then
         sign_define_cache[name] = s
      end
   end
   return sign_define_cache[name]
end

function M.define(name, opts, redefine)
   if redefine then
      sign_define_cache[name] = nil
      fn.sign_undefine(name)
      fn.sign_define(name, opts)
   elseif not sign_get(name) then
      fn.sign_define(name, opts)
   end
end

function M.remove(bufnr, lnum)
   if lnum then
      placed[bufnr][lnum] = nil
      scheduled[bufnr][lnum] = nil
   else
      placed[bufnr] = nil
      scheduled[bufnr] = nil
   end
   fn.sign_unplace(sign_group, { buffer = bufnr, id = lnum })
end

function M.schedule(cfg, bufnr, signs)
   if not cfg.signcolumn and not cfg.numhl and not cfg.linehl then

      return
   end

   for _, s in ipairs(signs) do
      local stype = M.sign_map[s.type]

      local cs = cfg.signs[s.type]
      if cfg.signcolumn and cs.show_count and s.count then
         local count = s.count
         local cc = cfg.count_chars
         local count_suffix = cc[count] and tostring(count) or (cc['+'] and 'Plus') or ''
         local count_char = cc[count] or cc['+'] or ''
         stype = stype .. count_suffix
         M.define(stype, {
            texthl = cs.hl,
            text = cfg.signcolumn and cs.text .. count_char or '',
            numhl = cfg.numhl and cs.numhl,
            linehl = cfg.linehl and cs.linehl,
         })
      end


      if not placed[bufnr][s.lnum] then
         scheduled[bufnr][s.lnum] = {
            id = s.lnum,
            group = sign_group,
            name = stype,
            buffer = bufnr,
            lnum = s.lnum,
            priority = cfg.sign_priority,
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

function M.get(bufnr, lnum)
   local s = (placed[bufnr] or {})[lnum]
   return s and s.name
end

return M
