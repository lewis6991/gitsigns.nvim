
local api = vim.api

local dprint = require("gitsigns.debug").dprint

local record M
  setup_highlight: function(string)
end

local enum GitSignHl
  'GitSignsAdd'
  'GitSignsChange'
  'GitSignsDelete'

  'GitSignsAddNr'
  'GitSignsChangeNr'
  'GitSignsDeleteNr'

  'GitSignsAddLn'
  'GitSignsChangeLn'
  'GitSignsDeleteLn'

  'GitSignsCurrentLineBlame'
end

local hls: {GitSignHl:{string}} = {
  GitSignsAdd    = {'GitGutterAdd'   , 'SignifySignAdd'   , 'DiffAddedGutter'   , 'diffAdded'  , 'DiffAdd'   },
  GitSignsChange = {'GitGutterChange', 'SignifySignChange', 'DiffModifiedGutter', 'diffChanged', 'DiffChange'},
  GitSignsDelete = {'GitGutterDelete', 'SignifySignDelete', 'DiffRemovedGutter' , 'diffRemoved', 'DiffDelete'},

  GitSignsAddNr    = {'GitGutterAddLineNr'   , 'GitSignsAdd'   , 'SignifySignAdd'   , 'DiffAddedGutter'   , 'diffAdded'  , 'DiffAdd'   },
  GitSignsChangeNr = {'GitGutterChangeLineNr', 'GitSignsChange', 'SignifySignChange', 'DiffModifiedGutter', 'diffChanged', 'DiffChange'},
  GitSignsDeleteNr = {'GitGutterDeleteLineNr', 'GitSignsDelete', 'SignifySignDelete', 'DiffRemovedGutter' , 'diffRemoved', 'DiffDelete'},

  GitSignsAddLn    = {'GitGutterAddLine'   , 'SignifyLineAdd'   , 'DiffAdd'   },
  GitSignsChangeLn = {'GitGutterChangeLine', 'SignifyLineChange', 'DiffChange'},
  GitSignsDeleteLn = {'GitGutterDeleteLine', 'SignifyLineDelete', 'DiffDelete'},

  GitSignsCurrentLineBlame = {'NonText'},
}

local function is_hl_set(hl_name: string): boolean
   -- TODO: this only works with `set termguicolors`
  local exists, hl = pcall(api.nvim_get_hl_by_name, hl_name, true)
  local color = hl.foreground or hl.background
  return exists and color ~= nil
end

local function isGitSignHl(hl: string): boolean
  return hls[hl as GitSignHl] ~= nil
end

-- Setup a GitSign* highlight by deriving it from other potentially present
-- highlights.
M.setup_highlight = function(hl_name: string)
  if not isGitSignHl(hl_name) then
    return
  end

  if is_hl_set(hl_name) then
    -- Already defined
    dprint(('Highlight %s is already defined'):format(hl_name))
    return
  end

  for _, d in ipairs(hls[hl_name as GitSignHl]) do
    if is_hl_set(d) then
      dprint(('Deriving %s from %s'):format(hl_name, d))
      local hl_cmd = ('highlight link %s %s'):format(hl_name, d)
      -- Run highlight commands in an autocmd so they are run after any `syntax
      -- clear` commands triggered by colorschemes.
      if vim.v.vim_did_enter == 1 then
        vim.cmd(hl_cmd)
      else
        vim.cmd(('autocmd VimEnter * ++once %s'):format(hl_cmd))
      end
      return
    end
  end

  dprint(('Unable to setup highlight %s'):format(hl_name))
end

return M
