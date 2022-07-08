local api = vim.api

local SignsConfig = require('gitsigns.config').Config.SignsConfig
local config = require('gitsigns.config').config

local B = require('gitsigns.signs.base')

local M: B = {}

local group_base = 'gitsigns_extmark_signs_'

function M.new(cfg: SignsConfig, name: string): B
  local self = setmetatable({} as B, {__index = M})
  self.config = cfg
  self.group = group_base..(name or '')
  self.ns = api.nvim_create_namespace(self.group)
  return self
end

function M:on_lines(buf: integer, _: integer, last_orig: integer, last_new: integer)
  -- Remove extmarks on line deletions to mimic
  -- the behaviour of vim signs.
  if last_orig > last_new then
    self:remove(buf, last_new+1, last_orig)
  end
end

function M:remove(bufnr: integer, start_lnum: integer, end_lnum: integer)
  if start_lnum then
    api.nvim_buf_clear_namespace(bufnr, self.ns, start_lnum-1, end_lnum or start_lnum)
  else
    api.nvim_buf_clear_namespace(bufnr, self.ns, 0, -1)
  end
end

function M:add(bufnr: integer, signs: {M.Sign})
  if not config.signcolumn and not config.numhl and not config.linehl then
    -- Don't place signs if it won't show anything
    return
  end

  local cfg = self.config

  for _, s in ipairs(signs) do
    if not self:contains(bufnr, s.lnum) then
      local cs = cfg[s.type]
      local text = cs.text
      if config.signcolumn and cs.show_count and s.count then
        local count = s.count
        local cc = config.count_chars
        local count_char = cc[count] or cc['+'] or ''
        text = cs.text..count_char
      end

      local ok, err = pcall(api.nvim_buf_set_extmark, bufnr, self.ns, s.lnum-1, -1, {
        id              = s.lnum,
        sign_text       = config.signcolumn and text or '',
        priority        = config.sign_priority,
        sign_hl_group   = cs.hl,
        number_hl_group = config.numhl and cs.numhl or nil,
        line_hl_group   = config.linehl and cs.linehl or nil,
      })

      if not ok and config.debug_mode then
        vim.schedule(function()
          error(table.concat({
            string.format('Error placing extmark on line %d', s.lnum),
            err
          }, '\n'))
        end)
      end
    end
  end
end

function M:contains(bufnr: integer, start: integer, last: integer): boolean
  local marks = api.nvim_buf_get_extmarks(
    bufnr, self.ns, {start-1, 0}, {last or start, 0}, {limit=1})
  return #marks > 0
end

function M:reset()
  for _, buf in ipairs(api.nvim_list_bufs()) do
    self:remove(buf)
  end
end

return M
