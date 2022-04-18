local config = require('gitsigns.config').config
local SignsConfig = require('gitsigns.config').Config.SignsConfig

local dprint = require('gitsigns.debug').dprint

local B = require('gitsigns.signs.base')

local M: B = {}

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

function M.new(cfg: SignsConfig, name: string): B
  init()
  return M.new(cfg, name)
end

return setmetatable(B, {
  __index = function(_, k: string): any
    return rawget(M as table, k)
  end
})
