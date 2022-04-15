local api = vim.api

local Config = require('gitsigns.config').Config
local nvim   = require('gitsigns.nvim')

local B = require('gitsigns.signs.base')

local M: B = {}

local ns_em: integer

-- Attach to each buffer in order to remove extmarks on line deletions to mimic
-- the behaviour of vim signs.
local function attach(bufnr: integer)
  bufnr = bufnr or api.nvim_get_current_buf()
  api.nvim_buf_attach(bufnr, false, {
    on_lines = function(_, buf: integer, _, _, last_orig: integer, last_new: integer)
      if last_orig > last_new then
        M.remove(buf, last_new+1, last_orig)
      end
    end
  })
end

local group = 'gitsigns_extmark_signs'

function M.setup(_redefine: boolean)
  ns_em = api.nvim_create_namespace(group)
  nvim.augroup(group)
  nvim.autocmd('BufRead', {
    group = group,
    callback = vim.schedule_wrap(function()
      attach()
    end)
  })

  -- Attach to all open buffers
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_loaded(buf) and api.nvim_buf_get_name(buf) ~= '' then
      attach(buf)
    end
  end
end

function M.draw(_bufnr: integer, _top: integer, _bot: integer): boolean
end

function M.remove(bufnr: integer, start_lnum: integer, end_lnum: integer)
  if start_lnum then
    api.nvim_buf_clear_namespace(bufnr, ns_em, start_lnum-1, end_lnum or start_lnum)
  else
    api.nvim_buf_clear_namespace(bufnr, ns_em, 0, -1)
  end
end

local function placed(bufnr: integer, start: integer, last: integer): boolean
  local marks = api.nvim_buf_get_extmarks(
    bufnr, ns_em,
    {start-1, 0},
    {last or start, 0},
    {limit=1}
  )
  return #marks > 0
end

function M.schedule(cfg: Config, bufnr: integer, signs: {M.Sign})
  if not cfg.signcolumn and not cfg.numhl and not cfg.linehl then
    -- Don't place signs if it won't show anything
    return
  end

  for _, s in ipairs(signs) do
    if not placed(bufnr, s.lnum) then
      local cs = cfg.signs[s.type]
      local text = cs.text
      if cfg.signcolumn and cs.show_count and s.count then
        local count = s.count
        local cc = cfg.count_chars
        local count_char = cc[count] or cc['+'] or ''
        text = cs.text..count_char
      end

      api.nvim_buf_set_extmark(bufnr, ns_em, s.lnum-1, -1, {
        id              = s.lnum,
        sign_text       = cfg.signcolumn and text or '',
        priority        = cfg.sign_priority,
        sign_hl_group   = cs.hl,
        number_hl_group = cfg.numhl and cs.numhl or nil,
        line_hl_group   = cfg.linehl and cs.linehl or nil,
      })
    end
  end
end

function M.add(cfg: Config, bufnr: integer, signs: {M.Sign})
  M.schedule(cfg, bufnr, signs)
end

function M.need_redraw(bufnr: integer, start: integer, last: integer): boolean
  return placed(bufnr, start, last)
end

return M
