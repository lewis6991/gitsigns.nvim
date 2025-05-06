local api = vim.api

local Config = require('gitsigns.config')
local config = Config.config

--- @param s string
--- @return string
local function capitalise(s)
  return s:sub(1, 1):upper() .. s:sub(2)
end

--- @class Gitsigns.Sign
--- @field type Gitsigns.SignType
--- @field count? integer
--- @field lnum integer

--- @class Gitsigns.Signs
--- @field name string
--- @field group string
--- @field config table<Gitsigns.SignType,Gitsigns.SignConfig>
--- @field staged boolean
--- @field ns integer
--- @field private _hl_cache table<Gitsigns.SignType,table<string,string>>
local M = {}

local km = {
  culhl = 'Cul',
  linehl = 'Ln',
  numhl = 'Nr',
  hl = '',
}

--- @param ty Gitsigns.SignType
--- @param kind 'hl'|'numhl'|'linehl'|'culhl'
--- @return string?
function M:hl(ty, kind)
  if kind ~= 'hl' and not config[kind] then
    return
  end

  self._hl_cache = self._hl_cache or {}
  self._hl_cache[ty] = self._hl_cache[ty] or {}

  if self._hl_cache[ty][kind] then
    return self._hl_cache[ty][kind]
  end

  local result = ('GitSigns%s%s%s'):format(self.staged and 'Staged' or '', capitalise(ty), km[kind])
  self._hl_cache[ty][kind] = result
  return result
end

--- @param buf integer
--- @param last_orig integer
--- @param last_new integer
function M:on_lines(buf, _, last_orig, last_new)
  -- Remove extmarks on line deletions to mimic
  -- the behaviour of vim signs.
  if last_orig > last_new then
    self:remove(buf, last_new + 1, last_orig)
  end
end

--- @param bufnr integer
--- @param start_lnum? integer
--- @param end_lnum? integer
function M:remove(bufnr, start_lnum, end_lnum)
  if start_lnum then
    api.nvim_buf_clear_namespace(bufnr, self.ns, start_lnum - 1, end_lnum or start_lnum)
  else
    api.nvim_buf_clear_namespace(bufnr, self.ns, 0, -1)
  end
end

---@param bufnr integer
---@param signs Gitsigns.Sign[]
--- @param filter? fun(line: integer):boolean
function M:add(bufnr, signs, filter)
  if not config.signcolumn and not config.numhl and not config.linehl then
    -- Don't place signs if it won't show anything
    return
  end

  for _, sign in ipairs(signs) do
    if (not filter or filter(sign.lnum)) and not self:contains(bufnr, sign.lnum) then
      local lnum, ty = sign.lnum, sign.type
      local cs = self.config[ty]
      local text = cs.text
      if config.signcolumn and cs.show_count and sign.count then
        local cc = config.count_chars
        local count_char = cc[sign.count] or cc['+'] or ''
        text = text .. count_char
      end

      local ok, err = pcall(api.nvim_buf_set_extmark, bufnr, self.ns, lnum - 1, 0, {
        id = lnum,
        sign_text = config.signcolumn and text or '',
        priority = config.sign_priority,
        sign_hl_group = self:hl(ty, 'hl'),
        number_hl_group = self:hl(ty, 'numhl'),
        line_hl_group = self:hl(ty, 'linehl'),
        cursorline_hl_group = self:hl(ty, 'culhl'),
      })

      if not ok and config.debug_mode then
        vim.schedule(function()
          error(table.concat({
            string.format('Error placing extmark on line %d', sign.lnum),
            err,
          }, '\n'))
        end)
      end
    end
  end
end

---@param bufnr integer
---@param start integer
---@param last? integer
---@return boolean
function M:contains(bufnr, start, last)
  local marks = api.nvim_buf_get_extmarks(
    bufnr,
    self.ns,
    { start - 1, 0 },
    { last or start - 1, 0 },
    { limit = 1 }
  )
  return #marks > 0
end

function M:reset()
  for _, buf in ipairs(api.nvim_list_bufs()) do
    self:remove(buf)
  end
end

--- @param staged? boolean
--- @return Gitsigns.Signs
function M.new(staged)
  local __FUNC__ = 'signs.init'
  local self = setmetatable({}, { __index = M })
  self.config = staged and config.signs_staged or config.signs
  Config.subscribe(staged and 'signs_staged' or 'signs', function()
    self.config = staged and config.signs_staged or config.signs
  end)
  self.staged = staged == true
  self.group = 'gitsigns_signs_' .. (staged and 'staged' or '')
  self.ns = api.nvim_create_namespace(self.group)
  return self
end

return M
