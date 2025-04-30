local api = vim.api

local Config = require('gitsigns.config')
local config = Config.config

--- @class Gitsigns.Sign
--- @field type Gitsigns.SignType
--- @field count? integer
--- @field lnum integer

--- @class Gitsigns.Signs
--- @field name string
--- @field group string
--- @field config table<Gitsigns.SignType,Gitsigns.SignConfig>
--- @field ns integer
local M = {}

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

  for _, s in ipairs(signs) do
    if (not filter or filter(s.lnum)) and not self:contains(bufnr, s.lnum) then
      local cs = self.config[s.type]
      local text = cs.text
      if config.signcolumn and cs.show_count and s.count then
        local count = s.count
        local cc = config.count_chars
        local count_char = cc[count] or cc['+'] or ''
        text = cs.text .. count_char
      end

      local ok, err = pcall(api.nvim_buf_set_extmark, bufnr, self.ns, s.lnum - 1, 0, {
        id = s.lnum,
        sign_text = config.signcolumn and text or '',
        priority = config.sign_priority,
        sign_hl_group = cs.hl,
        number_hl_group = config.numhl and cs.numhl or nil,
        line_hl_group = config.linehl and cs.linehl or nil,
        cursorline_hl_group = config.culhl and cs.culhl or nil,
      })

      if not ok and config.debug_mode then
        vim.schedule(function()
          error(table.concat({
            string.format('Error placing extmark on line %d', s.lnum),
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
  self.group = 'gitsigns_signs_' .. (staged and 'staged' or '')
  self.ns = api.nvim_create_namespace(self.group)
  return self
end

return M
