
local api = vim.api

local dprintf = require("gitsigns.debug").dprintf

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



M.setup_highlight = function(hl_name)
   if not isGitSignHl(hl_name) then
      return
   end

   if is_hl_set(hl_name) then

      dprintf('Highlight %s is already defined', hl_name)
      return
   end

   for _, d in ipairs(hls[hl_name]) do
      if is_hl_set(d) then
         dprintf('Deriving %s from %s', hl_name, d)
         vim.cmd(('highlight default link %s %s'):format(hl_name, d))
         return
      end
   end

   dprintf('Unable to setup highlight %s', hl_name)
end

return M
