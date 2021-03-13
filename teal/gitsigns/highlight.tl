
local api = vim.api

local dprint = require("gitsigns/debug").dprint

local M = {}

local enum GitSignHl
  'GitSignsAdd'
  'GitSignsChange'
  'GitSignsDelete'
end

local hls: {GitSignHl:{string}} = {
  GitSignsAdd    = { 'GitGutterAdd'   , 'SignifySignAdd'   , 'DiffAdd'    },
  GitSignsChange = { 'GitGutterChange', 'SignifySignChange', 'DiffChange' },
  GitSignsDelete = { 'GitGutterDelete', 'SignifySignDelete', 'DiffDelete' },
}

local function hl_link(to: string, from: string, reverse: boolean)
  local to_exists, _ = pcall(api.nvim_get_hl_by_name, to, false)
  if to_exists then
    return
  end

  if not reverse then
    vim.cmd(('highlight link %s %s'):format(to, from))
    return
  end

  local exists, hl = pcall(api.nvim_get_hl_by_name, from, true)
  if exists then
    local bg = hl.background and ('guibg=#%06x'):format(hl.background) or ''
    local fg = hl.foreground and ('guifg=#%06x'):format(hl.foreground) or ''
    vim.cmd(table.concat({'highlight', to, fg, bg, 'gui=reverse'}, ' '))
  end
end

local stdHl = {
  'DiffAdd',
  'DiffChange',
  'DiffDelete'
}

local function isStdHl(hl: string): boolean
  return vim.tbl_contains(stdHl, hl)
end

local function isGitSignHl(hl: string): boolean
  return hls[hl as GitSignHl] ~= nil
end

-- Setup a GitSign* highlight by deriving it from other potentially present
-- highlights.
function M.setup_highlight(hl_name0: string)
  if not isGitSignHl(hl_name0) then
    return
  end

  local hl_name = hl_name0 as GitSignHl

  local exists, hl = pcall(api.nvim_get_hl_by_name, hl_name, true)
  if exists and (hl.foreground or hl.background) then
    -- Alread defined
    return
  end

  for _, d in ipairs(hls[hl_name]) do
    local _, dhl = pcall(api.nvim_get_hl_by_name, d, true)
    local color = dhl.foreground or dhl.background
    if color then
      dprint(('Deriving %s from %s'):format(hl_name, d))
      if isStdHl(d) then
        hl_link(hl_name, d, true)
      else
        hl_link(hl_name, d)
      end
      return
    end
  end
end

function M.setup_other_highlight(hl: string, from_hl: string)
  local hl_pfx, hl_sfx = hl:sub(1, -3), hl:sub(-2, -1)
  if isGitSignHl(hl_pfx) and (hl_sfx == 'Ln' or hl_sfx == 'Nr') then
    dprint(('Deriving %s from %s'):format(hl, from_hl))
    hl_link(hl, from_hl, hl_sfx == 'Ln')
  end
end

return M
