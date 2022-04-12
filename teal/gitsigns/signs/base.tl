local Config = require('gitsigns.config').Config

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

  setup   : function(redefine: boolean)
  draw    : function(bufnr: integer, top: integer, bot: integer): boolean
  remove  : function(bufnr: integer, lnum: integer)
  schedule: function(cfg: Config, bufnr: integer, signs: {M.Sign})
  add     : function(cfg: Config, bufnr: integer, signs: {M.Sign})
end

return M
