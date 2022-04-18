local fn = vim.fn

local SignsConfig = require('gitsigns.config').Config.SignsConfig
local config = require('gitsigns.config').config

local setdefault = require('gitsigns.util').setdefault

local B = require('gitsigns.signs.base')

local M: B = {}

local enum SignName
  "GitSignsAdd"
  "GitSignsDelete"
  "GitSignsChange"
  "GitSignsTopDelete"
  "GitSignsChangeDelete"
end

local sign_map: {B.SignType:SignName} = {
  add          = "GitSignsAdd",
  delete       = "GitSignsDelete",
  change       = "GitSignsChange",
  topdelete    = "GitSignsTopDelete",
  changedelete = "GitSignsChangeDelete",
}

-- The internal representation of signs in Neovim is a linked list which is
-- slow to index. Also when a sign is added/removed, it causes the sign column
-- width to re-calculated which requires a full scan of the signs list.
--
-- To workaround these shortcomings, we add an abstraction layer to the signs
-- API which keeps track of which signs have already been placed in the buffer.
-- This allows us to:
--   - efficiently query placed signs.
--   - skip adding a sign if it has already been placed.


function M.draw(self: B, bufnr: integer, top: integer, bot: integer): boolean
  local to_place = {}
  for i = top, bot do
    if self.scheduled[bufnr][i] then
      to_place[#to_place+1] = self.scheduled[bufnr][i]
      self.placed[bufnr][i] = self.scheduled[bufnr][i]
      self.scheduled[bufnr][i]= nil
    end
  end
  if to_place[1] then
    fn.sign_placelist(to_place)
  end
end

local sign_define_cache = {}

local function sign_get(name: string): table
  if not sign_define_cache[name] then
    local s = fn.sign_getdefined(name)
    if not vim.tbl_isempty(s) then
      sign_define_cache[name] = s
    end
  end
  return sign_define_cache[name]
end


local function define_sign(name: string, opts: {string:any}, redefine: boolean)
  if redefine then
    sign_define_cache[name] = nil
    fn.sign_undefine(name)
    fn.sign_define(name, opts)
  elseif not sign_get(name) then
    fn.sign_define(name, opts)
  end
end

local function define_signs(obj: B, redefine: boolean)
  -- Define signs
  for t, name in pairs(sign_map) do
    local cs = obj.config[t]
    define_sign(name, {
      texthl = cs.hl,
      text   = config.signcolumn and cs.text or nil,
      numhl  = config.numhl      and cs.numhl,
      linehl = config.linehl     and cs.linehl
    }, redefine)
  end
end

local group_base = 'gitsigns_vimfn_signs_'

function M.new(cfg: SignsConfig, name: string): B
  local self = setmetatable({} as B, {__index = M})
  self.group = group_base..(name or '')
  self.config = cfg
  self.placed = {}
  self.scheduled = {}

  setdefault(self.placed)
  setdefault(self.scheduled)

  define_signs(self, false)

  return self
end

function M.remove(self: B, bufnr: integer, start_lnum: integer, end_lnum: integer)
  end_lnum = end_lnum or start_lnum

  if start_lnum then
    for lnum = start_lnum, end_lnum do
      self.placed[bufnr][lnum] = nil
      self.scheduled[bufnr][lnum] = nil
      fn.sign_unplace(self.group, {buffer = bufnr, id = lnum})
    end
  else
    self.placed[bufnr] = nil
    self.scheduled[bufnr] = nil
    fn.sign_unplace(self.group, {buffer = bufnr})
  end
end

function M.schedule(self: B, bufnr: integer, signs: {M.Sign})
  if not config.signcolumn and not config.numhl and not config.linehl then
    -- Don't place signs if it won't show anything
    return
  end

  local cfg = self.config
  for _, s in ipairs(signs) do
    local stype: string = sign_map[s.type]

    local cs = cfg[s.type]
    if config.signcolumn and cs.show_count and s.count then
      local count = s.count
      local cc = config.count_chars
      local count_suffix = cc[count] and tostring(count) or (cc['+'] and 'Plus') or ''
      local count_char   = cc[count]                     or  cc['+']             or ''
      stype = stype..count_suffix
      define_sign(stype, {
        texthl = cs.hl,
        text   = config.signcolumn and cs.text..count_char or '',
        numhl  = config.numhl      and cs.numhl,
        linehl = config.linehl     and cs.linehl
      })
    end

    if not self.placed[bufnr][s.lnum] then
      self.scheduled[bufnr][s.lnum] = {
        id       = s.lnum,
        group    = self.group,
        name     = stype,
        buffer   = bufnr,
        lnum     = s.lnum,
        priority = config.sign_priority
      }
    end
  end
end

function M.add(self: B, bufnr: integer, signs: {M.Sign})
  self:schedule(bufnr, signs)
  for _, s in ipairs(signs) do
    self:draw(bufnr, s.lnum, s.lnum)
  end
end

function M.need_redraw(self: B, bufnr: integer, start: integer, last: integer): boolean
  for i = start+1, last+1 do
    if self.placed[bufnr][i] then
      return true
    end
  end
  return false
end

function M.reset(self: B)
  self.placed = {}
  self.scheduled = {}
  setdefault(self.placed)
  setdefault(self.scheduled)
  fn.sign_unplace(self.group)
  define_signs(self, true)
end

return M
