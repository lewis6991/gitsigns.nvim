local api = vim.api

local SignsConfig = require('gitsigns.config').Config.SignsConfig
local config = require('gitsigns.config').config
local nvim   = require('gitsigns.nvim')

local B = require('gitsigns.signs.base')

local M: B = {}

-- Attach to each buffer in order to remove extmarks on line deletions to mimic
-- the behaviour of vim signs.
local function attach(obj: B, bufnr: integer)
  bufnr = bufnr or api.nvim_get_current_buf()
  api.nvim_buf_attach(bufnr, false, {
    on_lines = function(_, buf: integer, _, _, last_orig: integer, last_new: integer)
      if last_orig > last_new then
        obj:remove(buf, last_new+1, last_orig)
      end
    end
  })
end

local group_base = 'gitsigns_extmark_signs_'

function M.new(cfg: SignsConfig, name: string): B
  local self = setmetatable({} as B, {__index = M})
  self.config = cfg
  self.group = group_base..(name or '')
  self.ns = api.nvim_create_namespace(self.group)

  nvim.augroup(self.group)
  nvim.autocmd('BufRead', {
    group = self.group,
    callback = vim.schedule_wrap(function()
      attach(self)
    end)
  })

  -- Attach to all open buffers
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_loaded(buf) and api.nvim_buf_get_name(buf) ~= '' then
      attach(self, buf)
    end
  end

  return self
end

function M.draw(_self: B, _bufnr: integer, _top: integer, _bot: integer): boolean
end

function M.remove(self: B, bufnr: integer, start_lnum: integer, end_lnum: integer)
  if start_lnum then
    api.nvim_buf_clear_namespace(bufnr, self.ns, start_lnum-1, end_lnum or start_lnum)
  else
    api.nvim_buf_clear_namespace(bufnr, self.ns, 0, -1)
  end
end

local function placed(self: B, bufnr: integer, start: integer, last: integer): boolean
  local marks = api.nvim_buf_get_extmarks(
    bufnr, self.ns,
    {start-1, 0},
    {last or start, 0},
    {limit=1}
  )
  return #marks > 0
end

function M.schedule(self: B, bufnr: integer, signs: {M.Sign})
  if not config.signcolumn and not config.numhl and not config.linehl then
    -- Don't place signs if it won't show anything
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
        text = cs.text..count_char
      end

      api.nvim_buf_set_extmark(bufnr, self.ns, s.lnum-1, -1, {
        id              = s.lnum,
        sign_text       = config.signcolumn and text or '',
        priority        = config.sign_priority,
        sign_hl_group   = cs.hl,
        number_hl_group = config.numhl and cs.numhl or nil,
        line_hl_group   = config.linehl and cs.linehl or nil,
      })
    end
  end
end

function M.add(self: B, bufnr: integer, signs: {M.Sign})
  self:schedule(bufnr, signs)
end

function M.need_redraw(self: B, bufnr: integer, start: integer, last: integer): boolean
  return placed(self, bufnr, start, last)
end

function M.reset(self: B)
  for _, buf in ipairs(api.nvim_list_bufs()) do
    self:remove(buf)
  end
end

return M
