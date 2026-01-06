local api = vim.api

--- @class Gitsigns.Hldef
--- @field [integer] string
--- @field desc string
--- @field hidden? boolean
--- @field fg_factor? number

local nvim10 = vim.fn.has('nvim-0.10') == 1

local M = {}

--- Use array of dict so we can iterate deterministically
--- Export for docgen
--- @type table<string,Gitsigns.Hldef>[]
M.hls = {}

--- @param s string
--- @return string
local function capitalise(s)
  return s:sub(1, 1):upper() .. s:sub(2)
end

---@param staged boolean
---@param kind ''|'Nr'|'Ln'|'Cul'
---@param ty 'add'|'change'|'delete'|'changedelete'|'topdelete'|'untracked'
---@return string? highlight
---@return Gitsigns.Hldef? spec
local function gen_hl(staged, kind, ty)
  local cty = capitalise(ty)
  local hl = ('GitSigns%s%s%s'):format(staged and 'Staged' or '', cty, kind)

  if kind == 'Ln' and (ty == 'delete' or 'ty' == 'topdelete') then
    return
  end

  local what --- @type string
  if kind == 'Nr' then
    what = 'number column (when `config.numhl == true`)'
  elseif kind == 'Ln' then
    what = 'buffer line (when `config.linehl == true`)'
  elseif kind == 'Cul' then
    what = 'the text (when the cursor is on the same line as the sign)'
  else
    what = 'the text'
  end

  local fallbacks --- @type string[]
  if staged then
    fallbacks = { ('GitSigns%s%s'):format(cty, kind) }
  elseif ty == 'changedelete' then
    fallbacks = { 'GitSignsChange' .. kind }
  elseif ty == 'topdelete' then
    fallbacks = { 'GitSignsDelete' .. kind }
  elseif ty == 'untracked' then
    fallbacks = { 'GitSignsAdd' .. kind }
  elseif kind == 'Nr' then
    fallbacks = {
      ('GitGutter%sLineNr'):format(cty),
      ('GitSigns%s'):format(cty),
    }
  elseif kind == 'Ln' then
    fallbacks = {
      ('GitGutter%sLine'):format(cty),
      ('SignifyLine%s'):format(cty),
      ('Diff%s'):format(cty),
    }
  elseif kind == 'Cul' then
    fallbacks = { ('GitSigns%s'):format(cty) }
  else
    fallbacks = {
      ('GitGutter%s'):format(cty),
      ('SignifySign%s'):format(cty),

      ty == 'add' and 'DiffAddedGutter'
        or ty == 'delete' and 'DiffRemovedGutter'
        or ty == 'change' and 'DiffModifiedGutter'
        or '???',

      ty == 'add' and (nvim10 and 'Added' or 'diffAdded')
        or ty == 'delete' and (nvim10 and 'Removed' or 'diffRemoved')
        or ty == 'change' and (nvim10 and 'Changed' or 'diffChanged')
        or '???',

      ('Diff%s'):format(cty),
    }
  end

  local sty = (staged and 'staged ' or '')

  --- @type Gitsigns.Hldef
  local spec = {
    desc = ("Used for %s of '%s' %ssigns."):format(what, ty, sty),
    fg_factor = staged and 0.5 or nil,
    unpack(fallbacks),
  }

  return hl, spec
end

for _, staged in ipairs({ false, true }) do
  for _, kind in ipairs({ '', 'Nr', 'Ln', 'Cul' }) do
    for _, ty in ipairs({ 'add', 'change', 'delete', 'changedelete', 'topdelete', 'untracked' }) do
      local hl, spec = gen_hl(staged, kind, ty)
      if hl then
        table.insert(M.hls, { [hl] = spec })
      end
    end
  end
end

vim.list_extend(M.hls, {
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

  {
    GitSignsNoEOLPreview = {
      'DiffNoEOL',
      'Constant',
      desc = 'Used for "No newline at end of file".',
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
})

---@param name string
---@return vim.api.keyset.get_hl_info
local function get_hl(name)
  return api.nvim_get_hl(0, { name = name, link = false })
end

--- @param hl_name string
--- @return boolean
local function is_hl_set(hl_name)
  local hl = get_hl(hl_name)
  local color = hl.fg
    or hl.bg
    or hl.reverse
    or hl.ctermfg
    or hl.ctermbg
    or hl.cterm and hl.cterm.reverse
  return color ~= nil
end

--- @param x? integer
--- @param factor number
--- @return integer?
local function cmix(x, factor)
  if not x or factor == 0 then
    return x
  end

  local r = math.floor(x / 2 ^ 16)
  local x1 = x - (r * 2 ^ 16)
  local g = math.floor(x1 / 2 ^ 8)
  local b = math.floor(x1 - (g * 2 ^ 8))

  local function mix(c, target, f)
    return math.floor(c + (target - c) * f)
  end

  -- If positive, lighten by mixing with 255 (white)
  -- If negative, darken by mixing with 0 (black)
  local target = factor > 0 and 255 or 0
  factor = math.abs(factor)

  r = mix(r, target, factor)
  g = mix(g, target, factor)
  b = mix(b, target, factor)

  return math.floor(r * 2 ^ 16 + g * 2 ^ 8 + b)
end

local function dprintf(fmt, ...)
  dprintf = require('gitsigns.debug.log').dprintf
  dprintf(fmt, ...)
end

--- @param hl string
--- @param hldef Gitsigns.Hldef
--- @param is_bg_light boolean
local function derive(hl, hldef, is_bg_light)
  for _, d in ipairs(hldef) do
    if is_hl_set(d) then
      dprintf('Deriving %s from %s', hl, d)
      if hldef.fg_factor then
        local dh = get_hl(d)
        api.nvim_set_hl(0, hl, {
          default = true,
          fg = cmix(dh.fg, hldef.fg_factor * (is_bg_light and 1 or -1)),
          bg = dh.bg,
        })
      else
        api.nvim_set_hl(0, hl, { default = true, link = d })
      end
      return
    end
  end
  if hldef[1] and not hldef.fg_factor then
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
  local is_bg_light = vim.o.background == 'light'
  for _, hlg in ipairs(M.hls) do
    for hl, hldef in pairs(hlg) do
      if is_hl_set(hl) then
        -- Already defined
        dprintf('Highlight %s is already defined', hl)
      else
        derive(hl, hldef, is_bg_light)
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

do --- temperature highlight
  local temp_colors = {} --- @type table<integer,string>
  local normal_bg --- @type [integer,integer,integer]?

  --- @param min integer
  --- @param max integer
  --- @param t integer
  --- @param alpha number 0-1
  --- @param fg? boolean
  --- @return string
  function M.get_temp_hl(min, max, t, alpha, fg)
    local Color = require('gitsigns.color')

    local normalized_t = (t - min) / (math.max(max, t) - min)
    local raw_temp_color = Color.temp(normalized_t)

    if normal_bg == nil then
      local normal_hl = api.nvim_get_hl(0, { name = 'Normal' })
      if normal_hl.bg then
        normal_bg = Color.int_to_rgb(normal_hl.bg)
      elseif vim.o.background == 'light' then
        normal_bg = { 255, 255, 255 } -- white
      else
        normal_bg = { 0, 0, 0 } -- black
      end
    end

    local color = Color.rgb_to_int(Color.blend(raw_temp_color, normal_bg, alpha))

    if temp_colors[color] then
      return temp_colors[color]
    end

    local fgs = fg and 'fg' or 'bg'
    local hl_name = ('GitSignsColorTemp.%s.%d'):format(fgs, color)
    api.nvim_set_hl(0, hl_name, { [fgs] = color })
    temp_colors[color] = hl_name
    return hl_name
  end
end

return M
