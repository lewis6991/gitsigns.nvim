local SignsConfig = require('gitsigns.config').Config.SignsConfig

local record M
  enum SignType
    "add"
    "delete"
    "change"
    "topdelete"
    "changedelete"
  end

  record Sign
    type: SignType
    count: integer
    lnum: integer
  end

  group: string
  config: SignsConfig

  -- Used by signs/extmarks.tl
  ns: integer

  -- Used by signs/vimfn.tl
  placed: {integer:{integer:vim.fn.SignPlaceItem}}
  scheduled: {integer:{integer:vim.fn.SignPlaceItem}}

  new         : function(cfg: SignsConfig, name: string): M
  draw        : function(M, bufnr: integer, top: integer, bot: integer): boolean
  remove      : function(M, bufnr: integer, start_lnum: integer, end_lnum: integer)
  schedule    : function(M, bufnr: integer, signs: {M.Sign})
  add         : function(M, bufnr: integer, signs: {M.Sign})
  need_redraw : function(M, bufnr: integer, start: integer, last: integer): boolean
  reset       : function(M)
end

return M
