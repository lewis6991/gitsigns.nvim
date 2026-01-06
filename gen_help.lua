#!/usr/bin/env -S nvim -l
-- Simple script to update the help doc by reading the config schema.

local inspect = vim.inspect
local list_extend = vim.list_extend
local startswith = vim.startswith

local config = require('lua.gitsigns.config')

local INDENT = 4
local INDENT_STR = string.rep(' ', INDENT)

-- To make sure the output is consistent between runs (to minimise diffs), we
-- need to iterate through the schema keys in a deterministic way. To do this we
-- do a smple scan over the file the schema is defined in and collect the keys
-- in the order they are defined.
--- @return string[]
local function get_ordered_schema_keys()
  local ci = io.lines('lua/gitsigns/config.lua') --- @type Iterator[string]

  for l in ci do
    if startswith(l, 'M.schema = {') then
      break
    end
  end

  local keys = {}
  for l in ci do
    if startswith(l, '}') then
      break
    end
    if l:find('^  (%w+).*') then
      local lc = l:gsub('^%s*([%w_]+).*', '%1')
      table.insert(keys, lc)
    end
  end

  return keys
end

--- @alias EmmyDocLoc { file: string, line: integer }
--- @alias EmmyDocParam { name: string, typ: string, desc: string? }
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

--- @alias EmmyDocTypeMember EmmyDocTypeField | EmmyDocFn

--- @class EmmyDocTypeClass
--- @field type 'class'
--- @field name string
--- @field bases string[]?
--- @field members EmmyDocTypeMember[]

--- @class EmmyDocTypeAlias
--- @field type 'alias'
--- @field name string
--- @field members EmmyDocTypeMember[]

--- @alias EmmyDocType EmmyDocTypeClass | EmmyDocTypeAlias

--- @class EmmyDocJson
--- @field modules EmmyDocModule[]
--- @field types EmmyDocType[]?

--- @return EmmyDocJson
local function load_emmy_doc()
  local path = 'emydoc/doc.json'
  local raw = vim.fn.readfile(path)
  local json = table.concat(raw, '\n')
  return vim.json.decode(json, { luanil = { object = true, array = true } })
end

--- @param dep_info boolean|{new_field: string, message: string, hard: boolean}
--- @param out fun(_: string?)
local function gen_config_doc_deprecated(dep_info, out)
  if type(dep_info) == 'table' and dep_info.hard then
    out(INDENT_STR .. 'HARD-DEPRECATED')
  else
    out(INDENT_STR .. 'DEPRECATED')
  end
  if type(dep_info) == 'table' then
    if dep_info.message then
      out(INDENT_STR .. dep_info.message)
    end
    if dep_info.new_field then
      out('')
      local opts_key, field = dep_info.new_field:match('(.*)%.(.*)')
      if opts_key and field then
        out(
          (INDENT_STR .. 'Please instead use the field `%s` in |gitsigns-config-%s|.'):format(
            field,
            opts_key
          )
        )
      else
        out((INDENT_STR .. 'Please instead use |gitsigns-config-%s|.'):format(dep_info.new_field))
      end
    end
  end
  out('')
end

--- @class IndentDocOpts
--- @field dedent? boolean
--- @field dedent_start? integer
--- @field tilde_block? boolean

--- @param lines string[]
--- @param opts? IndentDocOpts
--- @return string[]
local function indent_lines(lines, opts)
  opts = opts or {}

  local dedent = opts.dedent
  if dedent == nil then
    dedent = true
  end

  local dedent_start = opts.dedent_start or 1
  local tilde_block = opts.tilde_block or false

  local min_pad --- @type integer?
  if dedent then
    for i = dedent_start, #lines do
      local line = lines[i]
      if line ~= '' and line ~= '<' then
        local pad = #(line:match('^%s*') or '')
        if not min_pad or pad < min_pad then
          min_pad = pad
        end
      end
    end
  end

  local res = {} --- @type string[]
  local in_tilde_block = false

  for i, line in ipairs(lines) do
    if line == '' or line == '<' then
      res[#res + 1] = line
    else
      local mp = dedent and (min_pad or 0) or 0
      if i < dedent_start then
        mp = 0
      end

      local extra = tilde_block and in_tilde_block and INDENT or 0
      res[#res + 1] = string.rep(' ', INDENT + extra) .. line:sub(mp + 1)
    end

    in_tilde_block = tilde_block and line:match(': ~%s*$') ~= nil
  end

  return res
end

--- @param v Gitsigns.SchemaElem
--- @return string
local function vtype(v)
  local ty = v.type_help or v.type
  if type(ty) == 'function' then
    error('type of type function must have type_help defined')
  elseif ty == 'table' and v.deep_extend then
    return 'table[extended]'
  elseif type(ty) == 'table' then
    --- @cast ty type[]
    return table.concat(ty, '|')
  end
  return ty
end

--- @param field string
--- @param out fun(_: string?)
local function gen_config_doc_field(field, out)
  local v = config.schema[field]

  -- Field heading and tag
  local t = ('*gitsigns-config-%s*'):format(field)
  if #field + #t < 80 then
    out(('%-29s %48s'):format(field, t))
  else
    out(('%-29s'):format(field))
    out(('%78s'):format(t))
  end

  local deprecated = v.deprecated
  if deprecated then
    gen_config_doc_deprecated(deprecated, out)
  end

  if v.description then
    local d --- @type string
    local default_help = v.default_help
    if default_help ~= nil then
      d = default_help
    else
      d = ('`%s`'):format(inspect(v.default))
    end

    if d:find('\n') then
      out((INDENT_STR .. 'Type: `%s`'):format(vtype(v)))
      out(INDENT_STR .. 'Default: >')
      local dlines = vim.split(d, '\n')
      while dlines[1] == '' do
        table.remove(dlines, 1)
      end
      while dlines[#dlines] == '' do
        table.remove(dlines, #dlines)
      end

      local normalized = indent_lines(dlines, { dedent_start = 2 })
      for _, line in ipairs(normalized) do
        out(line)
      end
      out('<')
    else
      out((INDENT_STR .. 'Type: `%s`, Default: %s'):format(vtype(v), d))
      out()
    end

    local desc_lines = vim.split(v.description:gsub(' +$', ''), '\n')
    while desc_lines[1] == '' do
      table.remove(desc_lines, 1)
    end
    while desc_lines[#desc_lines] == '' do
      table.remove(desc_lines, #desc_lines)
    end

    local normalized = indent_lines(desc_lines)
    for _, line in ipairs(normalized) do
      out(line)
    end
  end
end

--- @return string
local function gen_config_doc()
  local res = {} ---@type string[]

  local function out(line)
    res[#res + 1] = line or ''
  end

  local first = true
  for _, k in ipairs(get_ordered_schema_keys()) do
    if first then
      first = false
    else
      out('')
    end
    gen_config_doc_field(k, out)
  end
  return table.concat(res, '\n')
end

--- @param x string[]
--- @return string[]
local function trim_lines(x)
  local min_pad --- @type integer?
  for _, e in ipairs(x) do
    local _, i = e:find('^ *')
    if not min_pad or min_pad > i then
      min_pad = i
    end
  end

  local r = {} --- @type string[]
  for _, e in ipairs(x) do
    r[#r + 1] = e:sub(assert(min_pad) + 1)
  end

  return r
end

--- @param s string
--- @return string
local function md_links_to_vimdoc(s)
  return (s:gsub('%[%[([^%]]+)%]%]', '|%1|'))
end

local function parse_fence_lang(s)
  local lang = s:match('^```%s*([%w_-]+)%s*$')
  if lang then
    return lang
  end
  if s:match('^```%s*$') then
    return ''
  end
end

--- Convert a small markdown subset into vimdoc.
--- Supports:
--- - Unordered list items (`- foo`) -> (`- foo`)
--- - Code fences (```lua) -> (>lua) blocks
--- - `Examples:` + code fence -> `Examples: >lua` blocks
--- - `Attributes:` + bullet list -> `Attributes: ~` blocks
---
--- @param lines string[]
--- @return string[]
local function markdown_to_vimdoc(lines)
  local out = {} --- @type string[]

  local i = 1
  while i <= #lines do
    local line = assert(lines[i])
    local next_line = lines[i + 1]

    local indent = line:match('^%s*') or ''
    local trimmed = line:sub(#indent + 1)

    local handled = false

    if trimmed:match('^Examples?:%s*$') and type(next_line) == 'string' then
      local next_indent = next_line:match('^%s*') or ''
      local next_trimmed = next_line:sub(#next_indent + 1)
      local lang = parse_fence_lang(next_trimmed)
      if lang and lang ~= '' then
        handled = true
        out[#out + 1] = md_links_to_vimdoc(indent .. trimmed:gsub('%s*$', '') .. ' >' .. lang)
        i = i + 2
        while i <= #lines do
          local l = assert(lines[i])
          local l_indent = l:match('^%s*') or ''
          local l_trimmed = l:sub(#l_indent + 1)
          if l_trimmed:match('^```%s*$') then
            out[#out + 1] = '<'
            i = i + 1
            break
          end
          out[#out + 1] = l
          i = i + 1
        end
      end
    end

    if not handled and trimmed:match('^Attributes:%s*$') then
      handled = true
      out[#out + 1] = indent .. 'Attributes: ~'
      i = i + 1
      while i <= #lines do
        local l = assert(lines[i])
        local l_indent = l:match('^%s*') or ''
        local l_trimmed = l:sub(#l_indent + 1)
        if l_trimmed == '' then
          out[#out + 1] = ''
          i = i + 1
          break
        end
        local item = l_trimmed:match('^[-*+]%s+(.*)$')
        if not item then
          break
        end
        item = item:gsub('^`', ''):gsub('`$', '')
        out[#out + 1] = md_links_to_vimdoc(item)
        i = i + 1
      end
    end

    if not handled then
      local lang = parse_fence_lang(trimmed)
      if lang then
        handled = true
        out[#out + 1] = indent .. '>' .. lang
        i = i + 1
        while i <= #lines do
          local l = assert(lines[i])
          local l_indent = l:match('^%s*') or ''
          local l_trimmed = l:sub(#l_indent + 1)
          if l_trimmed:match('^```%s*$') then
            out[#out + 1] = '<'
            i = i + 1
            break
          end
          out[#out + 1] = l
          i = i + 1
        end
      end
    end

    if not handled then
      local item = trimmed:match('^[-*+]%s+(.*)$')
      if item then
        handled = true
        out[#out + 1] = md_links_to_vimdoc(indent .. '• ' .. item)
        i = i + 1
      end
    end

    if not handled then
      out[#out + 1] = md_links_to_vimdoc(line)
      i = i + 1
    end
  end

  return out
end

--- @param first_prefix string
--- @param next_prefix string
--- @param text string
--- @param max_width integer
--- @return string[]
local function wrap_words(first_prefix, next_prefix, text, max_width)
  if #first_prefix + #text <= max_width then
    return { first_prefix .. text }
  end

  local out = {} --- @type string[]
  local prefix = first_prefix
  local line = prefix
  local line_len = #line

  for word in text:gmatch('%S+') do
    local sep = (line_len == #prefix) and '' or ' '
    if line_len + #sep + #word > max_width then
      if line_len > #prefix then
        out[#out + 1] = line
        prefix = next_prefix
        line = prefix .. word
        line_len = #line
      else
        if prefix:match('^%s*$') then
          -- If indentation makes the first word exceed max_width, reduce indent.
          local keep = math.max(0, max_width - #word)
          out[#out + 1] = prefix:sub(1, keep) .. word
        else
          -- Fall back to putting the (long) word on its own line.
          out[#out + 1] = line .. sep .. word
        end
        prefix = next_prefix
        line = prefix
        line_len = #line
      end
    else
      line = line .. sep .. word
      line_len = #line
    end
  end

  if line_len > #prefix then
    out[#out + 1] = line
  end

  return out
end

--- @param line string
--- @param max_width integer
--- @return string[]
local function wrap_help_line(line, max_width)
  if #line <= max_width then
    return { line }
  end

  if line:match('^%s*$') or line:match('^%s*<%s*$') then
    return { line }
  end

  -- Don't wrap function tag headers; they rely on column alignment.
  if line:match('%*gitsigns%.') then
    return { line }
  end

  -- Param/return wrapping: keep the prefix (up to ': ') fixed and align continuations.
  local idx = line:find('): ')
  if idx then
    local prefix = line:sub(1, idx + 2)
    local rest = line:sub(idx + 3)
    return wrap_words(prefix, string.rep(' ', #prefix), rest, max_width)
  end

  local indent = line:match('^%s*') or ''
  local text = line:sub(#indent + 1)

  return wrap_words(indent, indent, text, max_width)
end

--- @param lines string[]
--- @param max_width integer
--- @return string[]
local function wrap_help_lines(lines, max_width)
  local out = {} --- @type string[]
  local in_block = false

  for _, line in ipairs(lines) do
    if in_block then
      out[#out + 1] = line
      if line:match('^%s*<%s*$') then
        in_block = false
      end
    else
      -- Help "literal" blocks (examples/defaults) start with a line ending in '>' or '>lang'.
      if line:match('>%s*$') or line:match('>%w+%s*$') then
        out[#out + 1] = line
        in_block = true
      else
        list_extend(out, wrap_help_line(line, max_width))
      end
    end
  end

  return out
end

--- @param ty EmmyDocTypeClass
--- @param classes table<string, EmmyDocTypeClass>
--- @param fields_seen? table<string,true>
--- @return EmmyDocTypeField[]
local function get_fields(ty, classes, fields_seen)
  fields_seen = fields_seen or {}
  local ret = {} --- @type EmmyDocTypeField[]

  for _, m in ipairs(ty.members or {}) do
    if not fields_seen[m.name] and m.type == 'field' then
      fields_seen[m.name] = true
      ret[#ret + 1] = m
    end
  end

  for _, b in ipairs(ty.bases or {}) do
    if classes[b] then
      list_extend(ret, get_fields(classes[b], classes))
    end
  end

  return ret
end

--- @param name? string
--- @param classes table<string, EmmyDocTypeClass>
--- @return string[]?
local function build_type_field_docs(name, classes)
  local t = classes[name]
  if not t then
    return
  end

  local lines = {} --- @type string[]

  for _, m in ipairs(get_fields(t, classes)) do
    if m.typ then
      lines[#lines + 1] = string.format('• {%s}: (`%s`)', m.name, m.typ:gsub('`', ''))
      if m.description and m.description ~= '' then
        lines[#lines + 1] = '  ' .. m.description
      end
    end
  end

  return lines
end

--- @param name? string
--- @param ty string
--- @param desc? string[]
--- @param name_pad? integer
--- @return string[]
local function render_param_or_return(name, ty, desc, name_pad)
  if type(ty) ~= 'string' then
    ty = 'any'
  end
  ty = ty:gsub('`', '')
  local ty_fmt = ('`%s`'):format(ty)

  name_pad = name_pad and (name_pad + 3) or 0
  local name_str = '' --- @type string

  if name == ':' then
    name_str = ''
  elseif name then
    local nf = '%-' .. tostring(name_pad) .. 's'
    name_str = nf:format(string.format('{%s} ', name))
  end

  desc = desc or {}

  if #desc == 0 then
    return { string.format('    %s(%s)', name_str, ty_fmt) }
  end

  local desc_vd = markdown_to_vimdoc(desc)

  local r = {} --- @type string[]

  local desc1_raw = assert(desc_vd[1]):gsub('^%s*:%s*', '')
  local desc1 = desc1_raw == '' and '' or ' ' .. desc1_raw
  r[#r + 1] = string.format('    %s(%s):%s', name_str, ty_fmt, desc1)

  local remain_desc = trim_lines(vim.list_slice(desc_vd, 2))
  for _, d in ipairs(remain_desc) do
    r[#r + 1] = '    ' .. string.rep(' ', name_pad) .. d
  end

  return r
end

--- @param header string
--- @param desc string[]
--- @param params [string, string, string[]][]
--- @param returns [string?, string, string[]?][]
--- @param deprecated string?
--- @return string[]
local function render_block(header, desc, params, returns, deprecated)
  local res = {}

  if deprecated then
    list_extend(res, {
      INDENT_STR .. 'DEPRECATED: ' .. md_links_to_vimdoc(deprecated),
      '',
    })
  end

  list_extend(res, indent_lines(markdown_to_vimdoc(desc), { dedent = false, tilde_block = true }))

  if #params > 0 then
    if res[#res] ~= '' then
      res[#res + 1] = ''
    end

    local param_block = { 'Parameters: ~' }

    local name_pad = 0
    for _, v in ipairs(params) do
      if #v[1] > name_pad then
        name_pad = #v[1]
      end
    end

    for _, v in ipairs(params) do
      local name, ty, pdesc = v[1], v[2], v[3]
      list_extend(param_block, render_param_or_return(name, ty, pdesc, name_pad))
    end
    list_extend(res, indent_lines(param_block, { dedent = false }))
  end

  if #returns > 0 then
    res[#res + 1] = ''
    local returns_block = { 'Returns: ~' }
    for _, v in ipairs(returns) do
      local name, ty, rdesc = v[1], v[2], v[3]
      list_extend(returns_block, render_param_or_return(name, ty, rdesc))
    end
    list_extend(res, indent_lines(returns_block, { dedent = false }))
  end

  res = wrap_help_lines(res, 80)
  table.insert(res, 1, header)

  return res
end

--- @param classes table<string, EmmyDocTypeClass>
--- @param class_name string
--- @return EmmyDocFn[]
local function get_class_functions(classes, class_name)
  local t = classes[class_name]
  if not t or t.type ~= 'class' then
    return {}
  end

  local res = {} --- @type EmmyDocFn[]
  for _, member in ipairs(t.members) do
    if member.type == 'fn' and not startswith(member.name, '_') then
      res[#res + 1] = member
    end
  end

  table.sort(res, function(a, b)
    return a.loc.line > b.loc.line
  end)

  return res
end

--- @param ty? string
--- @return string?
local function strip_optional(ty)
  if not ty then
    return
  end
  return (ty:gsub('%?$', ''))
end

--- @param classes table<string, EmmyDocTypeClass>
--- @param member EmmyDocFn
--- @return string[]
local function render_fn_block(classes, member)
  local args = {} --- @type string[]
  for _, p in ipairs(member.params) do
    args[#args + 1] = ('{%s}'):format(p.name)
  end

  local deprecated --- @type string?
  local desc = member.description and vim.split(member.description, '\n') or {}

  if member.deprecated then
    local dep_lines = vim.split(assert(member.deprecation_reason), '\n')
    deprecated = (dep_lines[1] or ''):gsub('^%s+', ''):gsub('%s+$', '')

    -- EmmyLua currently includes subsequent doc lines in the deprecation reason.
    -- Treat those as normal description text, stripping the one leading space
    -- it prefixes onto each line to preserve intended indentation.
    for i = 2, #dep_lines do
      desc[#desc + 1] = dep_lines[i]:gsub('^ ', '')
    end
  end

  local params = {} --- @type [string, string, string[]][]
  for _, p in ipairs(member.params) do
    local d = p.desc and vim.split(p.desc, '\n') or {}
    local type_field_docs = build_type_field_docs(strip_optional(p.typ), classes)
    if type_field_docs then
      list_extend(d, type_field_docs)
    end
    params[#params + 1] = { p.name, p.typ, d }
  end

  local returns = {} --- @type [string?, string, string[]?][]

  if not (#member.returns == 1 and member.returns[1].typ == 'nil') then
    for _, ret in ipairs(member.returns) do
      local d = type(ret.desc) == 'string' and vim.split(ret.desc, '\n') or {}
      returns[#returns + 1] = { ret.name, ret.typ, d }
    end
  end

  local sig = ('%s(%s)'):format(member.name, table.concat(args, ', '))
  local header = ('%-40s%38s'):format(sig, '*gitsigns.' .. member.name .. '()*')

  return render_block(header, desc, params, returns, deprecated)
end

--- @return string
local function gen_functions_doc()
  local doc = load_emmy_doc()
  local classes = {} --- @type table<string, EmmyDocTypeClass>
  for _, t in ipairs(doc.types or {}) do
    if t.type == 'class' then
      classes[t.name] = t
    end
  end

  local out = {} --- @type string[]

  for _, class_name in ipairs({ 'gitsigns.main', 'gitsigns.actions' }) do
    for _, member in ipairs(get_class_functions(classes, class_name)) do
      local b = render_fn_block(classes, member)
      for _, line in ipairs(b) do
        out[#out + 1] = line:match('^ *$') and '' or line
      end
      out[#out + 1] = ''
    end
  end
  return table.concat(out, '\n')
end

--- @return string
local function gen_highlights_doc()
  local res = {} --- @type string[]
  local highlights = require('lua.gitsigns.highlight')

  local name_max = 0
  for _, hl in ipairs(highlights.hls) do
    for name, _ in pairs(hl) do
      if name:len() > name_max then
        name_max = name:len()
      end
    end
  end

  for _, hl in ipairs(highlights.hls) do
    for name, spec in pairs(hl) do
      if not spec.hidden then
        local fallbacks_tbl = {} --- @type string[]
        for _, f in ipairs(spec) do
          fallbacks_tbl[#fallbacks_tbl + 1] = string.format('`%s`', f)
        end
        local fallbacks = table.concat(fallbacks_tbl, ', ')
        if spec.fg_factor then
          fallbacks = fallbacks .. (' (fg=%d%%)'):format(spec.fg_factor * 100)
        end
        res[#res + 1] = string.format('%s*hl-%s*', string.rep(' ', 56), name)
        res[#res + 1] = string.format('%s', name)
        if spec.desc then
          res[#res + 1] = string.format('%s%s', INDENT_STR, spec.desc)
          res[#res + 1] = ''
        end
        res[#res + 1] = string.format('%sFallbacks: %s', INDENT_STR, fallbacks)
      end
    end
  end

  return table.concat(res, '\n')
end

--- @return string
local function get_setup_from_readme()
  local readme = io.lines('README.md') --- @type Iterator[string]
  local res = {} --- @type string[]

  local function append(line)
    res[#res + 1] = line ~= '' and INDENT_STR .. line or ''
  end

  for l in readme do
    if l:match("require%('gitsigns'%).setup {") then
      append(l)
      break
    end
  end

  for l in readme do
    append(l)
    if l == '}' then
      break
    end
  end

  return table.concat(res, '\n')
end

--- @param marker string
--- @return string|fun():string
local function get_marker_text(marker)
  return ({
    VERSION = 'v1.0.2', -- x-release-please-version
    CONFIG = gen_config_doc,
    FUNCTIONS = gen_functions_doc,
    HIGHLIGHTS = gen_highlights_doc,
    SETUP = get_setup_from_readme,
  })[marker] or error('Unknown marker: ' .. marker)
end

local function main()
  local template = io.lines('etc/doc_template.txt') --- @type Iterator[string]

  local out = assert(io.open('doc/gitsigns.txt', 'w'))

  for l in template do
    local l1 = l
    local marker = l1:match('{{(.*)}}')
    if marker then
      local sub = get_marker_text(marker)
      if sub then
        if type(sub) == 'function' then
          sub = sub()
        end
        --- @type string
        sub = sub:gsub('%%', '%%%%')
        l1 = l1:gsub('{{' .. marker .. '}}', sub)
      end
    end
    out:write(l1 or '', '\n')
  end
end

main()
