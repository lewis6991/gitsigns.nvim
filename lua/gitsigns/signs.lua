local config = require('gitsigns.config').config
local dprint = require('gitsigns.debug').dprint

local B = require('gitsigns.signs.base')

local M = {}

local function init()
   local __FUNC__ = 'signs.init'
   if config._extmark_signs then
      dprint('Using extmark signs')
      M = require('gitsigns.signs.extmarks')
   else
      dprint('Using vimfn signs')
      M = require('gitsigns.signs.vimfn')
   end
end

function M.setup(redefine)
   init()
   M.setup(redefine)
end

return setmetatable(M, {
   __index = function(_, k)
      return rawget(M, k)
   end,
})
