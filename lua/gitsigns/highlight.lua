







local M = {}






M.hls = {
   { GitSignsAdd = { 'GitGutterAdd', 'SignifySignAdd', 'DiffAddedGutter', 'diffAdded', 'DiffAdd',
desc = "Used for the text of 'add' signs.",
}, },

   { GitSignsChange = { 'GitGutterChange', 'SignifySignChange', 'DiffModifiedGutter', 'diffChanged', 'DiffChange',
desc = "Used for the text of 'change' signs.",
}, },

   { GitSignsDelete = { 'GitGutterDelete', 'SignifySignDelete', 'DiffRemovedGutter', 'diffRemoved', 'DiffDelete',
desc = "Used for the text of 'delete' signs.",
}, },

   { GitSignsChangedelete = { 'GitSignsChange',
desc = "Used for the text of 'changedelete' signs.",
}, },

   { GitSignsTopdelete = { 'GitSignsDelete',
desc = "Used for the text of 'topdelete' signs.",
}, },

   { GitSignsUntracked = { 'GitSignsAdd',
desc = "Used for the text of 'untracked' signs.",
}, },

   { GitSignsAddNr = { 'GitGutterAddLineNr', 'GitSignsAdd',
desc = "Used for number column (when `config.numhl == true`) of 'add' signs.",
}, },

   { GitSignsChangeNr = { 'GitGutterChangeLineNr', 'GitSignsChange',
desc = "Used for number column (when `config.numhl == true`) of 'change' signs.",
}, },

   { GitSignsDeleteNr = { 'GitGutterDeleteLineNr', 'GitSignsDelete',
desc = "Used for number column (when `config.numhl == true`) of 'delete' signs.",
}, },

   { GitSignsChangedeleteNr = { 'GitSignsChangeNr',
desc = "Used for number column (when `config.numhl == true`) of 'changedelete' signs.",
}, },

   { GitSignsTopdeleteNr = { 'GitSignsDeleteNr',
desc = "Used for number column (when `config.numhl == true`) of 'topdelete' signs.",
}, },

   { GitSignsUntrackedNr = { 'GitSignsAddNr',
desc = "Used for number column (when `config.numhl == true`) of 'untracked' signs.",
}, },

   { GitSignsAddLn = { 'GitGutterAddLine', 'SignifyLineAdd', 'DiffAdd',
desc = "Used for buffer line (when `config.linehl == true`) of 'add' signs.",
}, },

   { GitSignsChangeLn = { 'GitGutterChangeLine', 'SignifyLineChange', 'DiffChange',
desc = "Used for buffer line (when `config.linehl == true`) of 'change' signs.",
}, },

   { GitSignsChangedeleteLn = { 'GitSignsChangeLn',
desc = "Used for buffer line (when `config.linehl == true`) of 'changedelete' signs.",
}, },

   { GitSignsUntrackedLn = { 'GitSignsAddLn',
desc = "Used for buffer line (when `config.linehl == true`) of 'untracked' signs.",
}, },




   { GitSignsStagedAdd = { 'GitSignsAdd', fg_factor = 0.5, hidden = true } },
   { GitSignsStagedChange = { 'GitSignsChange', fg_factor = 0.5, hidden = true } },
   { GitSignsStagedDelete = { 'GitSignsDelete', fg_factor = 0.5, hidden = true } },
   { GitSignsStagedTopdelete = { 'GitSignsTopdelete', fg_factor = 0.5, hidden = true } },
   { GitSignsStagedAddNr = { 'GitSignsAddNr', fg_factor = 0.5, hidden = true } },
   { GitSignsStagedChangeNr = { 'GitSignsChangeNr', fg_factor = 0.5, hidden = true } },
   { GitSignsStagedDeleteNr = { 'GitSignsDeleteNr', fg_factor = 0.5, hidden = true } },
   { GitSignsStagedTopdeleteNr = { 'GitSignsTopdeleteNr', fg_factor = 0.5, hidden = true } },
   { GitSignsStagedAddLn = { 'GitSignsAddLn', fg_factor = 0.5, hidden = true } },
   { GitSignsStagedChangeLn = { 'GitSignsChangeLn', fg_factor = 0.5, hidden = true } },

   { GitSignsAddPreview = { 'GitGutterAddLine', 'SignifyLineAdd', 'DiffAdd',
desc = "Used for added lines in previews.",
}, },

   { GitSignsDeletePreview = { 'GitGutterDeleteLine', 'SignifyLineDelete', 'DiffDelete',
desc = "Used for deleted lines in previews.",
}, },

   { GitSignsCurrentLineBlame = { 'NonText',
desc = "Used for current line blame.",
}, },

   { GitSignsAddInline = { 'TermCursor',
desc = "Used for added word diff regions in inline previews.",
}, },

   { GitSignsDeleteInline = { 'TermCursor',
desc = "Used for deleted word diff regions in inline previews.",
}, },

   { GitSignsChangeInline = { 'TermCursor',
desc = "Used for changed word diff regions in inline previews.",
}, },

   { GitSignsAddLnInline = { 'GitSignsAddInline',
desc = "Used for added word diff regions when `config.word_diff == true`.",
}, },

   { GitSignsChangeLnInline = { 'GitSignsChangeInline',
desc = "Used for changed word diff regions when `config.word_diff == true`.",
}, },

   { GitSignsDeleteLnInline = { 'GitSignsDeleteInline',
desc = "Used for deleted word diff regions when `config.word_diff == true`.",
}, },







   { GitSignsDeleteVirtLn = { 'GitGutterDeleteLine', 'SignifyLineDelete', 'DiffDelete',
desc = "Used for deleted lines shown by inline `preview_hunk_inline()` or `show_deleted()`.",
}, },

   { GitSignsDeleteVirtLnInLine = { 'GitSignsDeleteLnInline',
desc = "Used for word diff regions in lines shown by inline `preview_hunk_inline()` or `show_deleted()`.",
}, },

}

local function is_hl_set(hl_name)

   local exists, hl = pcall(vim.api.nvim_get_hl_by_name, hl_name, true)
   local color = hl.foreground or hl.background or hl.reverse
   return exists and color ~= nil
end

local function cmul(x, factor)
   if not x or factor == 1 then
      return x
   end

   local r = math.floor(x / 2 ^ 16)
   local x1 = x - (r * 2 ^ 16)
   local g = math.floor(x1 / 2 ^ 8)
   local b = math.floor(x1 - (g * 2 ^ 8))
   return math.floor(math.floor(r * factor) * 2 ^ 16 + math.floor(g * factor) * 2 ^ 8 + math.floor(b * factor))
end

local function derive(hl, hldef)
   local dprintf = require("gitsigns.debug").dprintf
   for _, d in ipairs(hldef) do
      if is_hl_set(d) then
         dprintf('Deriving %s from %s', hl, d)
         if hldef.fg_factor or hldef.bg_factor then
            hldef.fg_factor = hldef.fg_factor or 1
            hldef.bg_factor = hldef.bg_factor or 1
            local dh = vim.api.nvim_get_hl_by_name(d, true)
            vim.api.nvim_set_hl(0, hl, {
               default = true,
               fg = cmul(dh.foreground, hldef.fg_factor),
               bg = cmul(dh.background, hldef.bg_factor),
            })
         else
            vim.api.nvim_set_hl(0, hl, { default = true, link = d })
         end
         break
      end
   end
end



M.setup_highlights = function()
   local dprintf = require("gitsigns.debug").dprintf
   for _, hlg in ipairs(M.hls) do
      for hl, hldef in pairs(hlg) do
         if is_hl_set(hl) then

            dprintf('Highlight %s is already defined', hl)
         else
            derive(hl, hldef)
         end
      end
   end
end

return M
