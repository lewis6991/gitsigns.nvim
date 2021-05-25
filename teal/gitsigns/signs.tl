local Config = require('gitsigns.config').Config

local record M
  enum SignName
    "GitSignsAdd"
    "GitSignsDelete"
    "GitSignsChange"
    "GitSignsTopDelete"
    "GitSignsChangeDelete"
    "GitSignsEmpty"
  end

  enum SignType
    "add"
    "delete"
    "change"
    "topdelete"
    "changedelete"
    "empty"
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
  empty        = "GitSignsEmpty",
}

local ns = 'gitsigns_ns'

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
  if vim.tbl_isempty(opts) then
    return
  end
  if redefine then
    sign_define_cache[name] = nil
    vim.fn.sign_undefine(name)
    vim.fn.sign_define(name, opts)
  elseif not sign_get(name) then
    vim.fn.sign_define(name, opts)
  end
end

function M.remove(bufnr: integer, lnum: integer, sec: boolean)
  local sec_sfx = sec and 'Sec' or ''
  vim.fn.sign_unplace(ns..sec_sfx, {buffer = bufnr, id = lnum})
end

function M.add(cfg: Config, bufnr: integer, signs: {integer:M.Sign}, sec: boolean)
  local sec_sfx = sec and 'Sec' or ''

  local sign_cfg = sec and cfg.signs_sec or cfg.signs

  if not sign_cfg.signcolumn and not sign_cfg.numhl and not sign_cfg.linehl then
   -- Don't place signs if it won't show anything
   return
  end

  for lnum, s in pairs(signs) do
    local stype: string = M.sign_map[s.type]..sec_sfx
    local count = s.count

    local cs = sign_cfg[s.type]
    if sign_cfg.signcolumn and cs.show_count and count then
      local cc = cfg.count_chars
      local count_suffix = cc[count] and tostring(count) or (cc['+'] and 'Plus') or ''
      local count_char   = cc[count]                     or  cc['+']             or ''
      stype = stype..count_suffix
      M.define(stype, {
        texthl = cs.hl,
        text   = sign_cfg.signcolumn and cs.text..count_char or '',
        numhl  = sign_cfg.numhl      and cs.numhl,
        linehl = sign_cfg.linehl     and cs.linehl
      })
    end

    vim.fn.sign_place(lnum, ns..sec_sfx, stype, bufnr, {
      lnum = lnum,
      priority = cfg.sign_priority - (sec and 1 or 0)
    })
  end
end

-- Return map of line number to sign name. Can't use SignName as signs with
-- counts have a suffix on their name.
function M.get(bufnr: integer, lnum: integer, sec: boolean): {integer:string}
  local sec_sfx = sec and 'Sec' or ''
  local placed = vim.fn.sign_getplaced(bufnr, {group=ns..sec_sfx, id=lnum})[1].signs
  local ret = {}
  for _, s in ipairs(placed) do
    ret[s.id] = s.name
  end
  return ret
end

function M.has_empty(buf: integer): boolean
  return not vim.tbl_isempty(M.get(buf, nil, true))
end

function M.add_one(cfg: Config, buf: integer, lnum: integer, stype: M.SignType)
  M.add(cfg, buf, {[lnum] = {type=stype, count=0}})
end

function M.add_empty_sec(cfg: Config, buf: integer, lnum: integer)
  M.add(cfg, buf, {[lnum] = {type='empty', count=0}}, true)
end

return M
