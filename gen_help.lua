#!/bin/sh
_=[[
exec nvim -l "$0" "$@"
]]
-- Simple script to update the help doc by reading the config schema.

local inspect = vim.inspect
local config = require('lua.gitsigns.config')

function table.slice(tbl, first, last, step)
  local sliced = {}
  for i = first or 1, last or #tbl, step or 1 do
    sliced[#sliced+1] = tbl[i]
  end
  return sliced
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

-- To make sure the output is consistent between runs (to minimise diffs), we
-- need to iterate through the schema keys in a deterministic way. To do this we
-- do a smple scan over the file the schema is defined in and collect the keys
-- in the order they are defined.
--- @return string[]
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
    if l:find('^  (%w+).*') then
      local lc = l:gsub('^%s*([%w_]+).*', '%1')
      table.insert(keys, lc)
    end
  end

  return keys
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
    local d --- @type string
    if v.default_help ~= nil then
      d = v.default_help
    else
      d = inspect(v.default):gsub('\n', '\n    ')
      d = ('`%s`'):format(d)
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

--- @return string
local function gen_config_doc()
  local res = {} ---@type string[]
  local function out(line)
    res[#res+1] = line or ''
  end
  for _, k in ipairs(get_ordered_schema_keys()) do
    gen_config_doc_field(k, out)
  end
  return table.concat(res, '\n')
end

--- @param line string
--- @return string
local function parse_func_header(line)
  local func = line:match('%w+%.([%w_]+)')
  if not func then
    error('Unable to parse: '..line)
  end
  local args_raw =
    line:match('function%((.*)%)') or             -- M.name = function(args)
    line:match('function%s+%w+%.[%w_]+%((.*)%)')  -- function M.name(args)
  local args = {}
  for k in string.gmatch(args_raw, "([%w_]+)") do
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

--- @param path string
--- @return string
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
        local ok, header = pcall(parse_func_header, l)
        if ok then
          block[1] = header
          blocks[#blocks+1] = block
        end
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

--- @param files string[]
--- @return string
local function gen_functions_doc(files)
  local res = ''
  for _, path in ipairs(files) do
    res = res..'\n'..gen_functions_doc_from_file(path)
  end
  return res
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
          fallbacks_tbl[#fallbacks_tbl+1] = string.format('`%s`', f)
        end
        local fallbacks = table.concat(fallbacks_tbl, ', ')
        res[#res+1] = string.format('%s*hl-%s*', string.rep(' ', 56), name)
        res[#res+1] = string.format('%s', name)
        if spec.desc then
          res[#res+1] = string.format('%s%s', string.rep(' ', 8), spec.desc)
          res[#res+1] = ''
        end
        res[#res+1] = string.format('%sFallbacks: %s', string.rep(' ', 8), fallbacks)
      end
    end
  end

  return table.concat(res, '\n')
end

--- @return string
local function get_setup_from_readme()
  local i = read_file('README.md'):gmatch("([^\n]*)\n?")
  local res = {} --- @type string[]
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
    VERSION   = '0.7-dev',
    CONFIG    = function() return gen_config_doc() end,
    FUNCTIONS = function()
      return gen_functions_doc{
        'lua/gitsigns.lua',
        'lua/gitsigns/attach.lua',
        'lua/gitsigns/actions.lua',
      }
    end,
    HIGHLIGHTS = function() return gen_highlights_doc() end,
    SETUP     = function() return get_setup_from_readme() end,
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
