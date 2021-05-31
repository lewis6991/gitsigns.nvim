
local api = vim.api

local dprint = require("gitsigns.debug").dprint

local M = {}



local GitSignHl = {}















local hls = {
   GitSignsAdd = { 'GitGutterAdd', 'SignifySignAdd', 'DiffAddedGutter', 'diffAdded', 'DiffAdd' },
   GitSignsChange = { 'GitGutterChange', 'SignifySignChange', 'DiffModifiedGutter', 'diffChanged', 'DiffChange' },
   GitSignsDelete = { 'GitGutterDelete', 'SignifySignDelete', 'DiffRemovedGutter', 'diffRemoved', 'DiffDelete' },

   GitSignsAddNr = { 'GitGutterAddLineNr', 'GitSignsAdd', 'SignifySignAdd', 'DiffAddedGutter', 'diffAdded', 'DiffAdd' },
   GitSignsChangeNr = { 'GitGutterChangeLineNr', 'GitSignsChange', 'SignifySignChange', 'DiffModifiedGutter', 'diffChanged', 'DiffChange' },
   GitSignsDeleteNr = { 'GitGutterDeleteLineNr', 'GitSignsDelete', 'SignifySignDelete', 'DiffRemovedGutter', 'diffRemoved', 'DiffDelete' },

   GitSignsAddLn = { 'GitGutterAddLine', 'SignifyLineAdd', 'DiffAdd' },
   GitSignsChangeLn = { 'GitGutterChangeLine', 'SignifyLineChange', 'DiffChange' },
   GitSignsDeleteLn = { 'GitGutterDeleteLine', 'SignifyLineDelete', 'DiffDelete' },

   GitSignsCurrentLineBlame = { 'NonText' },
}

local function is_hl_set(hl_name)

   local exists, hl = pcall(api.nvim_get_hl_by_name, hl_name, true)
   local color = hl.foreground or hl.background
   return exists and color ~= nil
end

local function isGitSignHl(hl)
   return hls[hl] ~= nil
end



local function setup_highlight0(hl_name)
   if not isGitSignHl(hl_name) then
      return
   end

   if is_hl_set(hl_name) then

      dprint(('Highlight %s is already defined'):format(hl_name))
      return
   end

   for _, d in ipairs(hls[hl_name]) do
      if is_hl_set(d) then
         dprint(('Deriving %s from %s'):format(hl_name, d))
         vim.cmd(('highlight link %s %s'):format(hl_name, d))
         return
      end
   end

   dprint(('Unable to setup highlight %s'):format(hl_name))
end

M.setup_highlight = vim.schedule_wrap(setup_highlight0)

return M
