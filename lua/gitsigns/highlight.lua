local api = vim.api

local nvim = require('gitsigns.nvim')
local dprintf = require("gitsigns.debug").dprintf

local M = {}




local hls = {
   { GitSignsAdd = { 'GitGutterAdd', 'SignifySignAdd', 'DiffAddedGutter', 'diffAdded', 'DiffAdd' } },
   { GitSignsChange = { 'GitGutterChange', 'SignifySignChange', 'DiffModifiedGutter', 'diffChanged', 'DiffChange' } },
   { GitSignsDelete = { 'GitGutterDelete', 'SignifySignDelete', 'DiffRemovedGutter', 'diffRemoved', 'DiffDelete' } },

   { GitSignsAddNr = { 'GitGutterAddLineNr', 'GitSignsAdd' } },
   { GitSignsChangeNr = { 'GitGutterChangeLineNr', 'GitSignsChange' } },
   { GitSignsDeleteNr = { 'GitGutterDeleteLineNr', 'GitSignsDelete' } },

   { GitSignsAddLn = { 'GitGutterAddLine', 'SignifyLineAdd', 'DiffAdd' } },
   { GitSignsChangeLn = { 'GitGutterChangeLine', 'SignifyLineChange', 'DiffChange' } },



   { GitSignsAddPreview = { 'GitGutterAddLine', 'SignifyLineAdd', 'DiffAdd' } },
   { GitSignsDeletePreview = { 'GitGutterDeleteLine', 'SignifyLineDelete', 'DiffDelete' } },

   { GitSignsCurrentLineBlame = { 'NonText' } },

   { GitSignsAddInline = { 'TermCursor' } },
   { GitSignsDeleteInline = { 'TermCursor' } },
   { GitSignsChangeInline = { 'TermCursor' } },

   { GitSignsAddLnInline = { 'GitSignsAddInline' } },
   { GitSignsChangeLnInline = { 'GitSignsChangeInline' } },
   { GitSignsDeleteLnInline = { 'GitSignsDeleteInline' } },

   { GitSignsAddLnVirtLn = { 'GitSignsAddLn' } },
   { GitSignsChangeVirtLn = { 'GitSignsChangeLn' } },
   { GitSignsDeleteVirtLn = { 'GitGutterDeleteLine', 'SignifyLineDelete', 'DiffDelete' } },

   { GitSignsAddLnVirtLnInLine = { 'GitSignsAddLnInline' } },
   { GitSignsChangeVirtLnInLine = { 'GitSignsChangeLnInline' } },
   { GitSignsDeleteVirtLnInLine = { 'GitSignsDeleteLnInline' } },
}

local function is_hl_set(hl_name)

   local exists, hl = pcall(api.nvim_get_hl_by_name, hl_name, true)
   local color = hl.foreground or hl.background or hl.reverse
   return exists and color ~= nil
end



M.setup_highlights = function()
   for _, hlg in ipairs(hls) do
      for hl, candidates in pairs(hlg) do
         if is_hl_set(hl) then

            dprintf('Highlight %s is already defined', hl)
         else
            for _, d in ipairs(candidates) do
               if is_hl_set(d) then
                  dprintf('Deriving %s from %s', hl, d)
                  nvim.highlight(hl, { default = true, link = d })
                  break
               end
            end
         end
      end
   end
end

return M
