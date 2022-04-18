local api = vim.api

local dprintf = require("gitsigns.debug").dprintf

local record M
  setup_highlights: function()
end

local record Hldef
  {string}
  fg_factor: number
  bg_factor: number
end

-- Use array of dict so we can iterate deterministically
local hls: {{string:Hldef}} = {
  {GitSignsAdd                = {'GitGutterAdd'   , 'SignifySignAdd'   , 'DiffAddedGutter'   , 'diffAdded'  , 'DiffAdd'   }},
  {GitSignsChange             = {'GitGutterChange', 'SignifySignChange', 'DiffModifiedGutter', 'diffChanged', 'DiffChange'}},
  {GitSignsDelete             = {'GitGutterDelete', 'SignifySignDelete', 'DiffRemovedGutter' , 'diffRemoved', 'DiffDelete'}},

  {GitSignsAddNr              = {'GitGutterAddLineNr'   , 'GitSignsAdd'   }},
  {GitSignsChangeNr           = {'GitGutterChangeLineNr', 'GitSignsChange'}},
  {GitSignsDeleteNr           = {'GitGutterDeleteLineNr', 'GitSignsDelete'}},

  {GitSignsAddLn              = {'GitGutterAddLine'   , 'SignifyLineAdd'   , 'DiffAdd'   }},
  {GitSignsChangeLn           = {'GitGutterChangeLine', 'SignifyLineChange', 'DiffChange'}},
  -- Don't set GitSignsDeleteLn by default
  -- {GitSignsDeleteLn           = {}},

  {GitSignsStagedAdd                = {'GitSignsAdd'     , fg_factor = 0.5}},
  {GitSignsStagedChange             = {'GitSignsChange'  , fg_factor = 0.5}},
  {GitSignsStagedDelete             = {'GitSignsDelete'  , fg_factor = 0.5}},

  {GitSignsStagedAddNr              = {'GitSignsAddNr'   , fg_factor = 0.5}},
  {GitSignsStagedChangeNr           = {'GitSignsChangeNr', fg_factor = 0.5}},
  {GitSignsStagedDeleteNr           = {'GitSignsDeleteNr', fg_factor = 0.5}},

  {GitSignsStagedAddLn              = {'GitSignsAddLn'   , fg_factor = 0.5}},
  {GitSignsStagedChangeLn           = {'GitSignsChangeLn', fg_factor = 0.5}},

  {GitSignsAddPreview         = {'GitGutterAddLine'   , 'SignifyLineAdd'   , 'DiffAdd'   }},
  {GitSignsDeletePreview      = {'GitGutterDeleteLine', 'SignifyLineDelete', 'DiffDelete'}},

  {GitSignsCurrentLineBlame   = {'NonText'}},

  {GitSignsAddInline          = {'TermCursor'}},
  {GitSignsDeleteInline       = {'TermCursor'}},
  {GitSignsChangeInline       = {'TermCursor'}},

  {GitSignsAddLnInline        = {'GitSignsAddInline'}},
  {GitSignsChangeLnInline     = {'GitSignsChangeInline'}},
  {GitSignsDeleteLnInline     = {'GitSignsDeleteInline'}},

  {GitSignsAddLnVirtLn        = {'GitSignsAddLn'   }},
  {GitSignsChangeVirtLn       = {'GitSignsChangeLn'}},
  {GitSignsDeleteVirtLn       = {'GitGutterDeleteLine', 'SignifyLineDelete', 'DiffDelete'}},

  {GitSignsAddLnVirtLnInLine  = {'GitSignsAddLnInline'   }},
  {GitSignsChangeVirtLnInLine = {'GitSignsChangeLnInline'}},
  {GitSignsDeleteVirtLnInLine = {'GitSignsDeleteLnInline'}},
}

local function is_hl_set(hl_name: string): boolean
   -- TODO: this only works with `set termguicolors`
  local exists, hl = pcall(api.nvim_get_hl_by_name, hl_name, true)
  local color = hl.foreground or hl.background or hl.reverse
  return exists and color ~= nil
end

local function cmul(x: integer, factor: number): integer
  if not x or factor == 1 then
    return x
  end

  local r = math.floor(x / 2^16)
  local x1 = x - (r * 2^16)
  local g = math.floor(x1 / 2^8)
  local b = math.floor(x1 - (g * 2^8))
  return math.floor(math.floor(r*factor) * 2^16 + math.floor(g*factor) * 2^8 + math.floor(b*factor))
end

local function derive(hl: string, hldef: Hldef)
  for _, d in ipairs(hldef) do
    if is_hl_set(d) then
      dprintf('Deriving %s from %s', hl, d)
      if hldef.fg_factor or hldef.bg_factor then
        hldef.fg_factor = hldef.fg_factor or 1
        hldef.bg_factor = hldef.bg_factor or 1
        local dh = api.nvim_get_hl_by_name(d, true)
        api.nvim_set_hl(0, hl, {
          default = true,
          fg = cmul(dh.foreground, hldef.fg_factor),
          bg = cmul(dh.background, hldef.bg_factor),
        })
      else
        api.nvim_set_hl(0, hl, {default = true, link = d })
      end
      break
    end
  end
end

-- Setup a GitSign* highlight by deriving it from other potentially present
-- highlights.
M.setup_highlights = function()
  for _, hlg in ipairs(hls) do
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

return M
