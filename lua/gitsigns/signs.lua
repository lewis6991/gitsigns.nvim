local api = vim.api

local config = require('gitsigns.config').config

--- @class Gitsigns.Sign
--- @field type Gitsigns.SignType
--- @field count? integer
--- @field lnum integer

--- @class Gitsigns.Signs
--- @field hls table<Gitsigns.SignType,Gitsigns.SignConfig>
--- @field name string
--- @field group string
--- @field config table<string,Gitsigns.SignConfig>
--- @field ns integer
local M = {}

--- @param buf integer
--- @param last_orig? integer
--- @param last_new? integer
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
function M:add(bufnr, signs)
  if not config.signcolumn and not config.numhl and not config.linehl then
    -- Don't place signs if it won't show anything
    return
  end

  for _, s in ipairs(signs) do
    if not self:contains(bufnr, s.lnum) then
      local cs = self.config[s.type]
      local text = cs.text
      if config.signcolumn and cs.show_count and s.count then
        local count = s.count
        local cc = config.count_chars
        local count_char = cc[count] or cc['+'] or ''
        text = cs.text .. count_char
      end

      local hls = self.hls[s.type]

      local ok, err = pcall(api.nvim_buf_set_extmark, bufnr, self.ns, s.lnum - 1, -1, {
        id = s.lnum,
        sign_text = config.signcolumn and text or '',
        priority = config.sign_priority,
        sign_hl_group = hls.hl,
        number_hl_group = config.numhl and hls.numhl or nil,
        line_hl_group = config.linehl and hls.linehl or nil,
        cursorline_hl_group = config.culhl and hls.culhl or nil,
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
    { last or start, 0 },
    { limit = 1 }
  )
  return #marks > 0
end

function M:reset()
  for _, buf in ipairs(api.nvim_list_bufs()) do
    self:remove(buf)
  end
end

-- local function capitalise_word(x: string): string
--    return x:sub(1, 1):upper()..x:sub(2)
-- end

function M.new(cfg, name)
  local __FUNC__ = 'signs.init'

  -- Add when config.signs.*.[hl,numhl,linehl] are removed
  -- for _, t in ipairs {
  --    'add',
  --    'change',
  --    'delete',
  --    'topdelete',
  --    'changedelete',
  --    'untracked',
  -- } do
  --    local hl = string.format('GitSigns%s%s', name, capitalise_word(t))
  --    obj.hls[t] = {
  --       hl       = hl,
  --       numhl   = hl..'Nr',
  --       linehl = hl..'Ln',
  --    }
  -- end

  local self = setmetatable({}, { __index = M })
  self.config = cfg
  self.hls = name == 'staged' and config.signs_staged or config.signs
  self.group = 'gitsigns_signs_' .. (name or '')
  self.ns = api.nvim_create_namespace(self.group)
  return self
end

return M
