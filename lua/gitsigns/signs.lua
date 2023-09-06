local config = require('gitsigns.config').config

local dprint = require('gitsigns.debug.log').dprint

--- @class Gitsigns.Sign
--- @field type Gitsigns.SignType
--- @field count? integer
--- @field lnum integer

--- @class Gitsigns.Signs
--- @field hls table<Gitsigns.SignType,Gitsigns.SignConfig>
--- @field name string
--- @field group string
--- @field config table<string,Gitsigns.SignConfig>
--- Used by signs/extmarks.tl
--- @field ns integer
--- Used by signs/vimfn.tl
--- @field placed table<integer,table<integer,Gitsigns.Sign>>
--- @field new      fun(cfg: Gitsigns.SignConfig, name: string): Gitsigns.Signs
--- @field _new     fun(cfg: Gitsigns.SignConfig, hls: {SignType:Gitsigns.SignConfig}, name: string): Gitsigns.Signs
--- @field remove   fun(self: Gitsigns.Signs, bufnr: integer, start_lnum?: integer, end_lnum?: integer)
--- @field add      fun(self: Gitsigns.Signs, bufnr: integer, signs: Gitsigns.Sign[])
--- @field contains fun(self: Gitsigns.Signs, bufnr: integer, start: integer, last: integer): boolean
--- @field on_lines fun(self: Gitsigns.Signs, bufnr: integer, first: integer, last_orig: integer, last_new: integer)
--- @field reset    fun(self: Gitsigns.Signs)

local B = {
  Sign = {},
  HlDef = {},
}

-- local function capitalise_word(x: string): string
--    return x:sub(1, 1):upper()..x:sub(2)
-- end

function B.new(cfg, name)
  local __FUNC__ = 'signs.init'
  local C --- @type Gitsigns.Signs
  if config._extmark_signs then
    dprint('Using extmark signs')
    C = require('gitsigns.signs.extmarks')
  else
    dprint('Using vimfn signs')
    C = require('gitsigns.signs.vimfn')
  end

  local hls = name == 'staged' and config._signs_staged or config.signs
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
