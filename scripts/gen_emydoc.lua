local script_info = debug.getinfo(1, 'S')
--- @cast script_info -?
local script_dir = vim.fn.fnamemodify(script_info.source:sub(2), ':p:h')

--- @alias EmmyDocLoc { file: string, line: integer }
--- @alias EmmyDocTag { tag_name: string, content: string }
--- @alias EmmyDocParam { name: string, typ: string?, desc: string? }
--- @alias EmmyDocReturn { name: string?, typ: string, desc: string? }
--- @alias EmmyDocModule { name: string, members: EmmyDocFn[] }

--- @class EmmyDocFn
--- @field type 'fn'
--- @field name string
--- @field description string?
--- @field deprecated boolean
--- @field deprecation_reason string?
--- @field loc EmmyDocLoc
--- @field params EmmyDocParam[]
--- @field returns EmmyDocReturn[]

--- @class EmmyDocTypeField
--- @field type 'field'
--- @field name string
--- @field description string?
--- @field typ string

--- @alias EmmyDocTypeMember EmmyDocTypeField|EmmyDocFn

--- @class EmmyDocTypeClass
--- @field type 'class'
--- @field name string
--- @field bases string[]?
--- @field tag_content EmmyDocTag[]?
--- @field members EmmyDocTypeMember[]
--- @field description string?

--- @class EmmyDocTypeAlias
--- @field type 'alias'
--- @field name string
--- @field typ string
--- @field members EmmyDocTypeMember[]?

--- @alias EmmyDocType EmmyDocTypeClass|EmmyDocTypeAlias

--- @class EmmyDocJson
--- @field modules EmmyDocModule[]?
--- @field types EmmyDocType[]?

--- @class GenEmmyDoc
--- @field root string
--- @field load fun(): EmmyDocJson
--- @field strip_optional fun(typ: string): string, boolean

local M = {
  root = vim.fn.fnamemodify(script_dir, ':h'),
}

--- @return EmmyDocJson
function M.load()
  local raw = vim.fn.readfile(M.root .. '/emydoc/doc.json')
  return vim.json.decode(table.concat(raw, '\n'), { luanil = { object = true, array = true } })
end

--- @param typ string
--- @return string, boolean
function M.strip_optional(typ)
  local optional = false
  typ = vim.trim(typ)

  while vim.endswith(typ, '?') do
    optional = true
    typ = vim.trim(typ:sub(1, -2))
  end

  return typ, optional
end

return M
