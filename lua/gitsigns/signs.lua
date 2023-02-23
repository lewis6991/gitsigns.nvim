local config = require('gitsigns.config').config
local SignsConfig = require('gitsigns.config').Config.SignsConfig

local dprint = require('gitsigns.debug.log').dprint

local B = require('gitsigns.signs.base')

-- local function capitalise_word(x: string): string
--    return x:sub(1, 1):upper()..x:sub(2)
-- end

function B.new(cfg, name)
   local __FUNC__ = 'signs.init'
   local C
   if config._extmark_signs then
      dprint('Using extmark signs')
      C = require('gitsigns.signs.extmarks')
   else
      dprint('Using vimfn signs')
      C = require('gitsigns.signs.vimfn')
   end

   local hls = (name == 'staged' and config._signs_staged or config.signs)
   -- Add when config.signs.*.[hl,numhl,linehl] are removed
   -- for _, t in ipairs {
   --    'add',
   --    'change',
   --    'delete',
   --    'topdelete',
   --    'changedelete',
   --    'untracked',
   -- } do
   --    local hl = string.format('GitSigns%s%s', name, capitalise_word(t))
   --    obj.hls[t] = {
   --       hl       = hl,
   --       numhl   = hl..'Nr',
   --       linehl = hl..'Ln',
   --    }
   -- end
   return C._new(cfg, hls, name)
end

return B
