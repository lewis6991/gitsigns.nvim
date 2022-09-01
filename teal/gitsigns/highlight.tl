local api = vim.api

local nvim = require('gitsigns.nvim')
local dprintf = require("gitsigns.debug").dprintf

local record M
  setup_highlights: function()
end

-- Use array of dict so we can iterate deterministically
local hls: {{string:{string}}} = {
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

-- Setup a GitSign* highlight by deriving it from other potentially present
-- highlights.
M.setup_highlights = function()
  for _, hlg in ipairs(hls) do
    for hl, candidates in pairs(hlg) do
      if is_hl_set(hl) then
        -- Already defined
        dprintf('Highlight %s is already defined', hl)
      else
        for _, d in ipairs(candidates) do
          if is_hl_set(d) then
            dprintf('Deriving %s from %s', hl, d)
            nvim.highlight(hl, {default = true, link = d })
            break
          end
        end
      end
    end
  end
end

return M
