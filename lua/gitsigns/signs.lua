local config = require('gitsigns.config').config
local SignsConfig = require('gitsigns.config').Config.SignsConfig

local dprint = require('gitsigns.debug').dprint

local B = require('gitsigns.signs.base')





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
















   return C._new(cfg, hls, name)
end

return B
