local Config = require('gitsigns/config').Config

local record M
  enum SignName
    "GitSignsAdd"
    "GitSignsDelete"
    "GitSignsChange"
    "GitSignsTopDelete"
    "GitSignsChangeDelete"
  end

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
  end

  sign_map: {SignType:SignName}
end

M.sign_map = {
  add          = "GitSignsAdd",
  delete       = "GitSignsDelete",
  change       = "GitSignsChange",
  topdelete    = "GitSignsTopDelete",
  changedelete = "GitSignsChangeDelete",
}

local sign_define_cache = {}

local function sign_get(name: string): table
  if not sign_define_cache[name] then
    local s = vim.fn.sign_getdefined(name)
    if not vim.tbl_isempty(s) then
      sign_define_cache[name] = s
    end
  end
  return sign_define_cache[name]
end

function M.define(name: string, opts: {string:any}, redefine: boolean)
  if redefine then
    sign_define_cache[name] = nil
    vim.fn.sign_undefine(name)
    vim.fn.sign_define(name, opts)
  elseif not sign_get(name) then
    vim.fn.sign_define(name, opts)
  end
end

function M.remove(bufnr: integer, lnum: integer)
  vim.fn.sign_unplace('gitsigns_ns', {buffer = bufnr, id = lnum})
end

function M.add(cfg: Config, bufnr: integer, signs: {integer:M.Sign})
  for lnum, s in pairs(signs) do
    local stype: string = M.sign_map[s.type]
    local count = s.count

    local cs = cfg.signs[s.type]
    if cfg.signcolumn and cs.show_count and count then
      local cc = cfg.count_chars
      local count_suffix = cc[count] and tostring(count) or (cc['+'] and 'Plus') or ''
      local count_char   = cc[count]                     or  cc['+']             or ''
      stype = stype..count_suffix
      M.define(stype, {
        texthl = cs.hl,
        text   = cfg.signcolumn and cs.text..count_char or '',
        numhl  = cfg.numhl      and cs.numhl,
        linehl = cfg.linehl     and cs.linehl
      })
    end

    vim.fn.sign_place(lnum, 'gitsigns_ns', stype, bufnr, {
      lnum = lnum, priority = cfg.sign_priority
    })
  end
end

return M
