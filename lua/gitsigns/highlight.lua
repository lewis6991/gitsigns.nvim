local api = vim.api

--- @class Gitsigns.Hldef
--- @field [integer] string
--- @field desc string
--- @field hidden boolean
--- @field fg_factor number
--- @field bg_factor number

local M = {}

--- Use array of dict so we can iterate deterministically
--- Export for docgen
--- @type table<string,Gitsigns.Hldef>[]
M.hls = {
  {
    GitSignsAdd = {
      'GitGutterAdd',
      'SignifySignAdd',
      'DiffAddedGutter',
      'diffAdded',
      'DiffAdd',
      desc = "Used for the text of 'add' signs.",
    },
  },

  {
    GitSignsChange = {
      'GitGutterChange',
      'SignifySignChange',
      'DiffModifiedGutter',
      'diffChanged',
      'DiffChange',
      desc = "Used for the text of 'change' signs.",
    },
  },

  {
    GitSignsDelete = {
      'GitGutterDelete',
      'SignifySignDelete',
      'DiffRemovedGutter',
      'diffRemoved',
      'DiffDelete',
      desc = "Used for the text of 'delete' signs.",
    },
  },

  {
    GitSignsChangedelete = {
      'GitSignsChange',
      desc = "Used for the text of 'changedelete' signs.",
    },
  },

  { GitSignsTopdelete = { 'GitSignsDelete', desc = "Used for the text of 'topdelete' signs." } },

  { GitSignsUntracked = { 'GitSignsAdd', desc = "Used for the text of 'untracked' signs." } },

  {
    GitSignsAddNr = {
      'GitGutterAddLineNr',
      'GitSignsAdd',
      desc = "Used for number column (when `config.numhl == true`) of 'add' signs.",
    },
  },

  {
    GitSignsChangeNr = {
      'GitGutterChangeLineNr',
      'GitSignsChange',
      desc = "Used for number column (when `config.numhl == true`) of 'change' signs.",
    },
  },

  {
    GitSignsDeleteNr = {
      'GitGutterDeleteLineNr',
      'GitSignsDelete',
      desc = "Used for number column (when `config.numhl == true`) of 'delete' signs.",
    },
  },

  {
    GitSignsChangedeleteNr = {
      'GitSignsChangeNr',
      desc = "Used for number column (when `config.numhl == true`) of 'changedelete' signs.",
    },
  },

  {
    GitSignsTopdeleteNr = {
      'GitSignsDeleteNr',
      desc = "Used for number column (when `config.numhl == true`) of 'topdelete' signs.",
    },
  },

  {
    GitSignsUntrackedNr = {
      'GitSignsAddNr',
      desc = "Used for number column (when `config.numhl == true`) of 'untracked' signs.",
    },
  },

  {
    GitSignsAddLn = {
      'GitGutterAddLine',
      'SignifyLineAdd',
      'DiffAdd',
      desc = "Used for buffer line (when `config.linehl == true`) of 'add' signs.",
    },
  },

  {
    GitSignsChangeLn = {
      'GitGutterChangeLine',
      'SignifyLineChange',
      'DiffChange',
      desc = "Used for buffer line (when `config.linehl == true`) of 'change' signs.",
    },
  },

  {
    GitSignsChangedeleteLn = {
      'GitSignsChangeLn',
      desc = "Used for buffer line (when `config.linehl == true`) of 'changedelete' signs.",
    },
  },

  {
    GitSignsUntrackedLn = {
      'GitSignsAddLn',
      desc = "Used for buffer line (when `config.linehl == true`) of 'untracked' signs.",
    },
  },

  -- Don't set GitSignsDeleteLn by default
  -- {GitSignsDeleteLn = {}},

  { GitSignsStagedAdd = { 'GitSignsAdd', fg_factor = 0.5, hidden = true } },
  { GitSignsStagedChange = { 'GitSignsChange', fg_factor = 0.5, hidden = true } },
  { GitSignsStagedDelete = { 'GitSignsDelete', fg_factor = 0.5, hidden = true } },
  { GitSignsStagedChangedelete = { 'GitSignsChangedelete', fg_factor = 0.5, hidden = true } },
  { GitSignsStagedTopdelete = { 'GitSignsTopdelete', fg_factor = 0.5, hidden = true } },
  { GitSignsStagedAddNr = { 'GitSignsAddNr', fg_factor = 0.5, hidden = true } },
  { GitSignsStagedChangeNr = { 'GitSignsChangeNr', fg_factor = 0.5, hidden = true } },
  { GitSignsStagedDeleteNr = { 'GitSignsDeleteNr', fg_factor = 0.5, hidden = true } },
  { GitSignsStagedChangedeleteNr = { 'GitSignsChangedeleteNr', fg_factor = 0.5, hidden = true } },
  { GitSignsStagedTopdeleteNr = { 'GitSignsTopdeleteNr', fg_factor = 0.5, hidden = true } },
  { GitSignsStagedAddLn = { 'GitSignsAddLn', fg_factor = 0.5, hidden = true } },
  { GitSignsStagedChangeLn = { 'GitSignsChangeLn', fg_factor = 0.5, hidden = true } },
  { GitSignsStagedDeleteLn = { 'GitSignsDeleteLn', fg_factor = 0.5, hidden = true } },
  { GitSignsStagedChangedeleteLn = { 'GitSignsChangedeleteLn', fg_factor = 0.5, hidden = true } },
  { GitSignsStagedTopdeleteLn = { 'GitSignsTopdeleteLn', fg_factor = 0.5, hidden = true } },

  {
    GitSignsAddPreview = {
      'GitGutterAddLine',
      'SignifyLineAdd',
      'DiffAdd',
      desc = 'Used for added lines in previews.',
    },
  },

  {
    GitSignsDeletePreview = {
      'GitGutterDeleteLine',
      'SignifyLineDelete',
      'DiffDelete',
      desc = 'Used for deleted lines in previews.',
    },
  },

  { GitSignsCurrentLineBlame = { 'NonText', desc = 'Used for current line blame.' } },

  {
    GitSignsAddInline = {
      'TermCursor',
      desc = 'Used for added word diff regions in inline previews.',
    },
  },

  {
    GitSignsDeleteInline = {
      'TermCursor',
      desc = 'Used for deleted word diff regions in inline previews.',
    },
  },

  {
    GitSignsChangeInline = {
      'TermCursor',
      desc = 'Used for changed word diff regions in inline previews.',
    },
  },

  {
    GitSignsAddLnInline = {
      'GitSignsAddInline',
      desc = 'Used for added word diff regions when `config.word_diff == true`.',
    },
  },

  {
    GitSignsChangeLnInline = {
      'GitSignsChangeInline',
      desc = 'Used for changed word diff regions when `config.word_diff == true`.',
    },
  },

  {
    GitSignsDeleteLnInline = {
      'GitSignsDeleteInline',
      desc = 'Used for deleted word diff regions when `config.word_diff == true`.',
    },
  },

  -- Currently unused
  -- {GitSignsAddLnVirtLn = {'GitSignsAddLn'}},
  -- {GitSignsChangeVirtLn = {'GitSignsChangeLn'}},
  -- {GitSignsAddLnVirtLnInLine = {'GitSignsAddLnInline', }},
  -- {GitSignsChangeVirtLnInLine = {'GitSignsChangeLnInline', }},

  {
    GitSignsDeleteVirtLn = {
      'GitGutterDeleteLine',
      'SignifyLineDelete',
      'DiffDelete',
      desc = 'Used for deleted lines shown by inline `preview_hunk_inline()` or `show_deleted()`.',
    },
  },

  {
    GitSignsDeleteVirtLnInLine = {
      'GitSignsDeleteLnInline',
      desc = 'Used for word diff regions in lines shown by inline `preview_hunk_inline()` or `show_deleted()`.',
    },
  },

  {
    GitSignsVirtLnum = {
      'GitSignsDeleteVirtLn',
      desc = 'Used for line numbers in inline hunks previews.',
    },
  },
}

---@param name string
---@return table<string, any>
local function get_hl(name)
  --- @diagnostic disable-next-line:deprecated
  return api.nvim_get_hl_by_name(name, true)
end

--- @param hl_name string
--- @return boolean
local function is_hl_set(hl_name)
  -- TODO: this only works with `set termguicolors`
  local exists, hl = pcall(get_hl, hl_name)
  if not exists then
    return false
  end
  local color = hl.foreground or hl.background or hl.reverse
  return color ~= nil
end

--- @param x? number
--- @param factor number
--- @return number?
local function cmul(x, factor)
  if not x or factor == 1 then
    return x
  end

  local r = math.floor(x / 2 ^ 16)
  local x1 = x - (r * 2 ^ 16)
  local g = math.floor(x1 / 2 ^ 8)
  local b = math.floor(x1 - (g * 2 ^ 8))
  return math.floor(
    math.floor(r * factor) * 2 ^ 16 + math.floor(g * factor) * 2 ^ 8 + math.floor(b * factor)
  )
end

local function dprintf(fmt, ...)
  require('gitsigns.debug.log').dprintf(fmt, ...)
end

--- @param hl string
--- @param hldef Gitsigns.Hldef
local function derive(hl, hldef)
  for _, d in ipairs(hldef) do
    if is_hl_set(d) then
      dprintf('Deriving %s from %s', hl, d)
      if hldef.fg_factor or hldef.bg_factor then
        hldef.fg_factor = hldef.fg_factor or 1
        hldef.bg_factor = hldef.bg_factor or 1
        local dh = get_hl(d)
        api.nvim_set_hl(0, hl, {
          default = true,
          fg = cmul(dh.foreground, hldef.fg_factor),
          bg = cmul(dh.background, hldef.bg_factor),
        })
      else
        api.nvim_set_hl(0, hl, { default = true, link = d })
      end
      return
    end
  end
  if hldef[1] and not hldef.bg_factor and not hldef.fg_factor then
    -- No fallback found which is set. Just link to the first fallback
    -- if there are no modifiers
    dprintf('Deriving %s from %s', hl, hldef[1])
    api.nvim_set_hl(0, hl, { default = true, link = hldef[1] })
  else
    dprintf('Could not derive %s', hl)
  end
end

--- Setup a GitSign* highlight by deriving it from other potentially present
--- highlights.
function M.setup_highlights()
  for _, hlg in ipairs(M.hls) do
    for hl, hldef in pairs(hlg) do
      if is_hl_set(hl) then
        -- Already defined
        dprintf('Highlight %s is already defined', hl)
      else
        derive(hl, hldef)
      end
    end
  end
end

function M.setup()
  M.setup_highlights()
  api.nvim_create_autocmd('ColorScheme', {
    group = 'gitsigns',
    callback = M.setup_highlights,
  })
end

return M
