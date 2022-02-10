#!/bin/sh
_=[[
exec lua "$0" "$@"
]]
-- Simple script to update the help doc by reading the config schema.

local inspect = require('inspect')
local config = require('lua.gitsigns.config')

function table.slice(tbl, first, last, step)
  local sliced = {}
  for i = first or 1, last or #tbl, step or 1 do
    sliced[#sliced+1] = tbl[i]
  end
  return sliced
end

local function is_simple_type(t)
  return t == 'number' or t == 'string' or t == 'boolean'
end

local function startswith(str, start)
   return str.sub(str, 1, string.len(start)) == start
end

local function read_file(path)
  local f = assert(io.open(path, 'r'))
  local t = f:read("*all")
  f:close()
  return t
end

local function read_file_lines(path)
  local lines = {}
  for l in read_file(path):gmatch("([^\n]*)\n?") do
    table.insert(lines, l)
  end
  return lines
end

-- To make sure the output is consistent between runs (to minimise diffs), we
-- need to iterate through the schema keys in a deterministic way. To do this we
-- do a smple scan over the file the schema is defined in and collect the keys
-- in the order they are defined.
local function get_ordered_schema_keys()
  local c = read_file('lua/gitsigns/config.lua')

  local ci = c:gmatch("[^\n\r]+")

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
    if l:find('^   (%w+).*') then
      local lc = l:gsub('^%s*([%w_]+).*', '%1')
      table.insert(keys, lc)
    end
  end

  return keys
end

local function get_default(field)
  local cfg = read_file_lines('teal/gitsigns/config.tl')

  local fs, fe
  for i = 1, #cfg do
    local l = cfg[i]
    if l:match('^  '..field..' =') then
      fs = i
    end
    if fs and l:match('^  }') then
      fe = i
      break
    end
  end

  local ds, de
  for i = fs, fe do
    local l = cfg[i]
    if l:match('^    default =') then
      ds = i
      if l:match('},') or l:match('nil,') or l:match("default = '.*'") then
        de = i
        break
      end
    end
    if ds and l:match('^    }') then
      de = i
      break
    end
  end

  local ret = {}
  for i = ds, de do
    local l = cfg[i]
    if i == ds then
      l = l:gsub('%s*default = ', '')
    end
    if i == de then
      l = l:gsub('(.*),', '%1')
    end
    table.insert(ret, l)
  end

  return table.concat(ret, '\n')
end

local function gen_config_doc_deprecated(dep_info, out)
  if type(dep_info) == 'table' and dep_info.hard then
    out('   HARD-DEPRECATED')
  else
    out('   DEPRECATED')
  end
  if type(dep_info) == 'table' then
    if dep_info.message then
      out('      '..dep_info.message)
    end
    if dep_info.new_field then
      out('')
      local opts_key, field = dep_info.new_field:match('(.*)%.(.*)')
      if opts_key and field then
        out(('   Please instead use the field `%s` in |gitsigns-config-%s|.'):format(field, opts_key))
      else
        out(('   Please instead use |gitsigns-config-%s|.'):format(dep_info.new_field))
      end
    end
  end
  out('')
end

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

  if v.deprecated then
    gen_config_doc_deprecated(v.deprecated, out)
  end

  if v.description then
    local d
    if v.default_help ~= nil then
      d = v.default_help
    elseif is_simple_type(v.type) then
      d = inspect(v.default)
      d = ('`%s`'):format(d)
    else
      d = get_default(field)
      if d:find('\n') then
        d = d:gsub('\n([^\n\r])', '\n%1')
      else
        d = ('`%s`'):format(d)
      end
    end

    local vtype = (function()
      if v.type == 'table' and v.deep_extend then
        return 'table[extended]'
      end
      if type(v.type) == 'table' then
        v.type = table.concat(v.type, '|')
      end
      return v.type
    end)()

    if d:find('\n') then
      out(('      Type: `%s`'):format(vtype))
      out('      Default: >')
      out('        '..d:gsub('\n([^\n\r])', '\n    %1'))
      out('<')
    else
      out(('      Type: `%s`, Default: %s'):format(vtype, d))
      out()
    end

    out(v.description:gsub(' +$', ''))
  end
end

local function gen_config_doc()
  local res = {}
  local function out(line)
    res[#res+1] = line or ''
  end
  for _, k in ipairs(get_ordered_schema_keys()) do
    gen_config_doc_field(k, out)
  end
  return table.concat(res, '\n')
end

local function parse_func_header(line)
  local func = line:match('%.([^ ]+)')
  if not func then
    error('Unable to parse: '..line)
  end
  local args_raw = line:match('function%((.*)%)')
  local args = {}
  for k in string.gmatch(args_raw, "([%w_]+):") do
    if k:sub(1, 1) ~= '_' then
      args[#args+1] = string.format('{%s}', k)
    end
  end
  return string.format(
    '%-40s%38s',
    string.format('%s(%s)', func, table.concat(args, ', ')),
    '*gitsigns.'..func..'()*'
  )
end

local function gen_functions_doc_from_file(path)
  local i = read_file(path):gmatch("([^\n]*)\n?")

  local res = {}
  local blocks = {}
  local block = {''}

  local in_block = false
  for l in i do
    local l1 = l:match('^%-%-%- ?(.*)')
    if l1 then
      in_block = true
      if l1 ~= '' and l1 ~= '<' then
        l1 = '                '..l1
      end
      block[#block+1] = l1
    else
      if in_block then
        -- First line after block
        block[1] = parse_func_header(l)
        blocks[#blocks+1] = block
        block = {''}
      end
      in_block = false
    end
  end

  for j = #blocks, 1, -1 do
    local b = blocks[j]
    for k = 1, #b do
      res[#res+1] = b[k]
    end
    res[#res+1] = ''
  end

  return table.concat(res, '\n')
end

local function gen_functions_doc(files)
  local res = ''
  for _, path in ipairs(files) do
    res = res..'\n'..gen_functions_doc_from_file(path)
  end
  return res
end

local function get_setup_from_readme()
  local i = read_file('README.md'):gmatch("([^\n]*)\n?")
  local res = {}
  local function append(line)
      res[#res+1] = line ~= '' and '    '..line or ''
  end
  for l in i do
    if l:match("require%('gitsigns'%).setup {") then
      append(l)
      break
    end
  end

  for l in i do
    append(l)
    if l == '}' then
      break
    end
  end

  return table.concat(res, '\n')
end

local function get_marker_text(marker)
  return ({
    VERSION   = '0.3-dev',
    CONFIG    = gen_config_doc,
    FUNCTIONS = gen_functions_doc{
      'teal/gitsigns.tl',
      'teal/gitsigns/actions.tl',
    },
    SETUP     = get_setup_from_readme
  })[marker]
end

local function main()
  local i = read_file('etc/doc_template.txt'):gmatch("([^\n]*)\n?")

  local out = io.open('doc/gitsigns.txt', 'w')

  for l in i do
    local marker = l:match('{{(.*)}}')
    if marker then
      local sub = get_marker_text(marker)
      if sub then
        if type(sub) == 'function' then
          sub = sub()
        end
        sub = sub:gsub('%%', '%%%%')
        l = l:gsub('{{'..marker..'}}', sub)
      end
    end
    out:write(l or '', '\n')
  end
end

main()
