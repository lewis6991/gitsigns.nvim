#!/usr/bin/env -S nvim -l

local script_info = debug.getinfo(1, 'S')
--- @cast script_info -?
local root = vim.fn.fnamemodify(script_info.source:sub(2), ':p:h')
package.path = table.concat({
  root .. '/?.lua',
  root .. '/lua/?.lua',
  root .. '/lua/?/init.lua',
  package.path,
}, ';')

local emydoc = require('gen_emydoc') --- @type GenEmmyDoc
local actions = require('gitsigns.actions')
local strip_optional = emydoc.strip_optional

--- @class GeneratedPositionalSpec
--- @field name string
--- @field boolean? boolean
--- @field revision? boolean
--- @field required? boolean
--- @field values? string[]

--- @alias GeneratedFlagSpec false|true|string[]

--- @class GeneratedActionSpec
--- @field positional GeneratedPositionalSpec[]?
--- @field flags table<string, GeneratedFlagSpec>?

--- @param types table<string, EmmyDocTypeClass>
--- @param name string
--- @return EmmyDocTypeField[]
local function resolve_fields(types, name)
  local typ = types[name]

  local fields = {} --- @type EmmyDocTypeField[]
  local indexed = {} --- @type table<string, integer>

  for _, base in ipairs(typ.bases or {}) do
    for _, field in ipairs(resolve_fields(types, base)) do
      if not indexed[field.name] then
        indexed[field.name] = #fields + 1
        fields[#fields + 1] = field
      end
    end
  end

  for _, member in ipairs(typ.members) do
    if member.type == 'field' then
      local field = member
      local idx = indexed[field.name]
      if idx then
        fields[idx] = field
      else
        indexed[field.name] = #fields + 1
        fields[#fields + 1] = field
      end
    end
  end

  return fields
end

--- @param typ string
--- @return string
local function unwrap_parens(typ)
  typ = vim.trim(typ)

  while typ:match('^%b()$') do
    typ = vim.trim(typ:sub(2, -2))
  end

  return typ
end

--- @param typ string
--- @return string[]
local function split_union(typ)
  local parts = vim.split(unwrap_parens(typ), '|', { plain = true }) --- @type string[]
  for i, part in ipairs(parts) do
    parts[i] = unwrap_parens(part)
  end
  return parts
end

--- @param values string[]
--- @param value string
local function add_value(values, value)
  for _, existing in ipairs(values) do
    if existing == value then
      return
    end
  end

  values[#values + 1] = value
end

--- @param typ string
--- @return string?
local function get_literal(typ)
  local literal = typ:match("^'([^']+)'$") or typ:match('^"([^"]+)"$')
  if literal ~= nil then
    return literal
  end

  if typ == 'true' or typ == 'false' or typ:match('^%-?%d+$') then
    return typ
  end
end

--- @param aliases table<string, string>
--- @param typ string?
--- @param f fun(typ: string)
--- @return boolean
local function visit_type(aliases, typ, f)
  if not typ then
    return false
  end

  typ = vim.trim(typ)
  local optional = false
  typ, optional = strip_optional(typ)
  typ = unwrap_parens(typ)

  local union = split_union(typ)
  if #union > 1 then
    for _, item in ipairs(union) do
      optional = visit_type(aliases, item, f) or optional
    end
    return optional
  end

  if typ == 'nil' then
    return true
  end

  local alias = aliases[typ]
  if alias then
    return visit_type(aliases, alias, f) or optional
  end

  f(typ)
  return optional
end

--- @param param EmmyDocParam
--- @return boolean
local function is_callback_param(param)
  if param.name == 'callback' or param.name == '...' then
    return true
  end

  if not param.typ then
    return false
  end

  local typ = unwrap_parens((strip_optional(param.typ)))
  return vim.startswith(typ, 'fun(')
end

--- @param aliases table<string, string>
--- @param typ string?
--- @return string?
local function resolve_named_type(aliases, typ)
  if not typ then
    return
  end

  typ = unwrap_parens((strip_optional(typ)))

  while aliases[typ] do
    local alias = unwrap_parens((strip_optional(aliases[typ])))
    if #split_union(alias) > 1 then
      break
    end
    typ = alias
  end

  return typ
end

--- @param aliases table<string, string>
--- @param classes table<string, EmmyDocTypeClass>
--- @param param EmmyDocParam
--- @return boolean
local function is_opts_param(aliases, classes, param)
  if param.name ~= 'opts' then
    return false
  end

  local typ = resolve_named_type(aliases, param.typ)
  return typ ~= nil and classes[typ] ~= nil
end

--- @param param EmmyDocParam
--- @param aliases table<string, string>
--- @param later_scalar_count integer
--- @return GeneratedPositionalSpec
local function make_positional_spec(param, aliases, later_scalar_count)
  local spec = { name = param.name } --- @type GeneratedPositionalSpec
  local is_revision_name = param.name == 'base' or param.name == 'revision'
  local values = {} --- @type string[]
  local optional = visit_type(aliases, param.typ, function(typ)
    local elem = typ:match('^(.-)%[%]$')
    if elem then
      typ = elem
    end

    local literal = get_literal(typ)
    if literal then
      add_value(values, literal)
      if is_revision_name and literal == 'FILE' then
        spec.revision = true
      end
      return
    end

    if typ == 'boolean' then
      spec.boolean = true
    elseif is_revision_name and typ == 'string' then
      spec.revision = true
    end
  end)
  local skippable = optional
    and (
      later_scalar_count > 0
      or (
        param.desc ~= nil
        and (
          param.desc:find('`nil`', 1, true) ~= nil
          or param.desc:match('%f[%w]nil%f[^%w]') ~= nil
        )
      )
    )
  if #values > 0 then
    spec.values = values
  end

  if not skippable then
    spec.required = true
  end

  return spec
end

--- @param aliases table<string, string>
--- @param classes table<string, EmmyDocTypeClass>
--- @param typ string?
--- @return GeneratedFlagSpec?
local function make_flag_spec(aliases, classes, typ)
  local values = {} --- @type string[]
  local boolean = false
  local list = false
  local placeholder = false
  local complex = false

  visit_type(aliases, typ, function(part)
    local elem = part:match('^(.-)%[%]$')
    if elem then
      list = true
      part = elem
    end

    local literal = get_literal(part)
    if literal then
      add_value(values, literal)
    elseif part == 'boolean' then
      boolean = true
    elseif part == 'integer' or part == 'number' or part == 'string' then
      placeholder = true
    elseif part:match('^table<') or part:match('^fun%(') or classes[part] then
      complex = true
    else
      complex = true
    end
  end)

  if list then
    return
  end

  if boolean and #values == 0 and not placeholder and not complex then
    return false
  end

  if #values > 0 then
    return values
  end

  if not placeholder then
    return
  end

  return true
end

--- @param doc EmmyDocJson
--- @return table<string, GeneratedActionSpec>
local function build_action_specs(doc)
  local doc_types = doc.types
  --- @cast doc_types EmmyDocType[]
  local aliases = {} --- @type table<string, string>
  local classes = {} --- @type table<string, EmmyDocTypeClass>

  for _, typ in ipairs(doc_types) do
    if typ.type == 'alias' then
      aliases[typ.name] = typ.typ
    elseif typ.type == 'class' then
      classes[typ.name] = typ
    end
  end

  local actions_type = classes['gitsigns.actions']
  --- @cast actions_type EmmyDocTypeClass

  local ret = {} --- @type table<string, GeneratedActionSpec>

  for _, member in ipairs(actions_type.members) do
    if member.type == 'fn' and actions._supports_generated_cmp(member.name) then
      local positionals = {} --- @type GeneratedPositionalSpec[]
      local flags = {} --- @type table<string, GeneratedFlagSpec>
      local params = member.params or {}
      local scalar_count = 0

      for _, param in ipairs(params) do
        if not is_callback_param(param) and not is_opts_param(aliases, classes, param) then
          scalar_count = scalar_count + 1
        end
      end

      for _, param in ipairs(params) do
        if is_callback_param(param) then
          -- Ignore callback-only parameters.
        elseif is_opts_param(aliases, classes, param) then
          local type_name = resolve_named_type(aliases, param.typ)
          --- @cast type_name string
          for _, field in ipairs(resolve_fields(classes, type_name)) do
            local flag = make_flag_spec(aliases, classes, field.typ)
            if flag ~= nil then
              flags[field.name] = flag
            end
          end
        else
          scalar_count = scalar_count - 1
          positionals[#positionals + 1] = make_positional_spec(param, aliases, scalar_count)

          if param.name == 'global' then
            local flag = make_flag_spec(aliases, classes, param.typ)
            if flag ~= nil then
              flags[param.name] = flag
            end
          end
        end
      end

      if #positionals > 0 or next(flags) ~= nil then
        ret[member.name] = {
          positional = #positionals > 0 and positionals or nil,
          flags = next(flags) ~= nil and flags or nil,
        }
      end
    end
  end

  return ret
end

--- @param doc EmmyDocJson
--- @return string
local function render(doc)
  return table.concat({
    '-- This file is auto-generated by gen_completion.lua.\n',
    'return ',
    vim.inspect({ actions = build_action_specs(doc) }),
    '\n',
  })
end

local doc = emydoc.load()
local output = render(doc)

vim.fn.mkdir(root .. '/lua/gitsigns/cli/completion', 'p')
vim.fn.writefile(
  vim.split(output, '\n', { plain = true }),
  root .. '/lua/gitsigns/cli/completion/generated.lua'
)
