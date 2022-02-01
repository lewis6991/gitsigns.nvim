
local api = vim.api

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
   { GitSignsDeleteLn = { 'GitGutterDeleteLine', 'SignifyLineDelete', 'DiffDelete' } },

   { GitSignsCurrentLineBlame = { 'NonText' } },

   { GitSignsAddInline = { 'TermCursor' } },
   { GitSignsDeleteInline = { 'TermCursor' } },
   { GitSignsChangeInline = { 'TermCursor' } },

   { GitSignsAddLnInline = { 'GitSignsAddInline' } },
   { GitSignsChangeLnInline = { 'GitSignsChangeInline' } },
   { GitSignsDeleteLnInline = { 'GitSignsDeleteInline' } },

   { GitSignsAddLnVirtLn = { 'GitSignsAddLn' } },
   { GitSignsChangeVirtLn = { 'GitSignsChangeLn' } },
   { GitSignsDeleteVirtLn = { 'GitSignsDeleteLn' } },

   { GitSignsAddLnVirtLnInLine = { 'GitSignsAddLnInline' } },
   { GitSignsChangeVirtLnInLine = { 'GitSignsChangeLnInline' } },
   { GitSignsDeleteVirtLnInLine = { 'GitSignsDeleteLnInline' } },
}

local function is_hl_set(hl_name)

   local exists, hl = pcall(api.nvim_get_hl_by_name, hl_name, true)
   local color = hl.foreground or hl.background or hl.reverse
   return exists and color ~= nil
end

local hl_default_link
if vim.version().minor >= 7 then
   hl_default_link = function(from, to)
      api.nvim_set_hl(0, from, { default = true, link = to })
   end
else
   hl_default_link = function(from, to)
      vim.cmd(('highlight default link %s %s'):format(from, to))
   end
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
                  hl_default_link(hl, d)
                  break
               end
            end
         end
      end
   end
end

return M
