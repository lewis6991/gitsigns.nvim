#!/bin/sh
_=[[
exec nvim -l "$0" "$@"
]]
-- Simple script to update the help doc by reading the config schema.

local inspect = vim.inspect
local list_extend = vim.list_extend
local startswith = vim.startswith

local config = require('lua.gitsigns.config')

--- @param path string
--- @return string
local function read_file(path)
  local f = assert(io.open(path, 'r'))
  local t = f:read('*all')
  f:close()
  return t
end

-- To make sure the output is consistent between runs (to minimise diffs), we
-- need to iterate through the schema keys in a deterministic way. To do this we
-- do a smple scan over the file the schema is defined in and collect the keys
-- in the order they are defined.
--- @return string[]
local function get_ordered_schema_keys()
  local ci = read_file('lua/gitsigns/config.lua'):gmatch('[^\n\r]+')

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

--- @param dep_info boolean|{new_field: string, message: string, hard: boolean}
--- @param out fun(_: string?)
local function gen_config_doc_deprecated(dep_info, out)
  if type(dep_info) == 'table' and dep_info.hard then
    out('   HARD-DEPRECATED')
  else
    out('   DEPRECATED')
  end
  if type(dep_info) == 'table' then
    if dep_info.message then
      out('      ' .. dep_info.message)
    end
    if dep_info.new_field then
      out('')
      local opts_key, field = dep_info.new_field:match('(.*)%.(.*)')
      if opts_key and field then
        out(
          ('   Please instead use the field `%s` in |gitsigns-config-%s|.'):format(field, opts_key)
        )
      else
        out(('   Please instead use |gitsigns-config-%s|.'):format(dep_info.new_field))
      end
    end
  end
  out('')
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
      local ty = v.type
      if type(ty) == 'table' then
        v.type = table.concat(ty, '|')
      end
      return v.type
    end)()

    if d:find('\n') then
      out(('      Type: `%s`'):format(vtype))
      out('      Default: >')
      out('        ' .. d:gsub('\n([^\n\r])', '\n    %1'))
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
    res[#res + 1] = line or ''
  end

  for _, k in ipairs(get_ordered_schema_keys()) do
    gen_config_doc_field(k, out)
  end
  return table.concat(res, '\n')
end

--- @param line string
--- @return string
local function parse_func_header(line)
  -- match:
  --   prefix.name = ...
  --   function prefix.name(...
  local func = line:match('^%w+%.([%w_]+) =')
    or line:match('^function %w+%.([%w_]+)%(')
  if not func then
    error('Unable to parse: ' .. line)
  end
  local args_raw = line:match('function%((.*)%)') -- M.name = function(args)
    or line:match('function%s+%w+%.[%w_]+%((.*)%)') -- function M.name(args)
  local args = {} --- @type string[]
  for k in string.gmatch(args_raw, '([%w_]+)') do
    if k:sub(1, 1) ~= '_' then
      args[#args + 1] = string.format('{%s}', k)
    end
  end
  return string.format(
    '%-40s%38s',
    string.format('%s(%s)', func, table.concat(args, ', ')),
    '*gitsigns.' .. func .. '()*'
  )
end

--- @param x string
--- @return string? name
--- @return string? type
--- @return string? description
local function parse_param(x)
  local name, ty, des = x:match('([^ ]+) +([^ ]+) *(.*)')
  return name, ty, des
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
    r[#r + 1] = e:sub(min_pad + 1)
  end

  return r
end

--- @param name string
--- @param ty string
--- @param desc string[]
--- @param name_pad? integer
--- @return string[]
local function render_param_or_return(name, ty, desc, name_pad)
  ty = ty:gsub('Gitsigns%.%w+', 'table')

  name_pad = name_pad and (name_pad + 3) or 0
  local name_str --- @type string

  if name == ':' then
    name_str = ''
  else
    local nf = '%-' .. tostring(name_pad) .. 's'
    name_str = nf:format(string.format('{%s} ', name))
  end

  if #desc == 0 then
    return { string.format('    %s(%s)', name_str, ty) }
  end

  local r = {} --- @type string[]

  local desc1 = desc[1] == '' and '' or ' ' .. desc[1]
  r[#r + 1] = string.format('    %s(%s):%s', name_str, ty, desc1)

  local remain_desc = trim_lines(vim.list_slice(desc, 2))
  for _, d in ipairs(remain_desc) do
    r[#r + 1] = '    ' .. string.rep(' ', name_pad) .. d
  end

  return r
end

--- @param x string[]
--- @param amount integer
--- @return string[]
local function pad(x, amount)
  local pad_str = string.rep(' ', amount)

  local r = {} --- @type string[]
  for _, e in ipairs(x) do
    r[#r + 1] = pad_str .. e
  end
  return r
end

--- @param state EmmyState
--- @param doc_comment string
--- @param desc string[]
--- @param params {[1]: string, [2]: string, [3]: string[]}[]
--- @param returns {[1]: string, [2]: string, [3]: string[]}[]
--- @return EmmyState
local function process_doc_comment(state, doc_comment, desc, params, returns)
  if state == 'none' then
    state = 'in_block'
  end

  local emmy_type, emmy_str = doc_comment:match(' ?@([a-z]+) (.*)')

  if emmy_type == 'param' then
    local name, ty, pdesc = parse_param(emmy_str)
    params[#params + 1] = { name, ty, { pdesc } }
    return 'in_param'
  end

  if emmy_type == 'return' then
    local ty, name, rdesc = parse_param(emmy_str)
    returns[#returns + 1] = { name, ty, { rdesc } }
    return 'in_return'
  end

  if state == 'in_param' then
    -- Consume any remaining doc document lines as the description for the
    -- last parameter
    local lastdes = params[#params][3]
    lastdes[#lastdes + 1] = doc_comment
  elseif state == 'in_return' then
    -- Consume any remaining doc document lines as the description for the
    -- last return
    local lastdes = returns[#returns][3]
    lastdes[#lastdes + 1] = doc_comment
  else
    if doc_comment ~= '' and doc_comment ~= '<' then
      doc_comment = string.rep(' ', 16) .. doc_comment
    end
    desc[#desc + 1] = doc_comment
  end

  return state
end

--- @param header string
--- @param block string[]
--- @param params {[1]: string, [2]: string, [3]: string[]}[]
--- @param returns {[1]: string, [2]: string, [3]: string[]}[]
--- @return string[]?
local function render_block(header, block, params, returns)
  if vim.startswith(header, '_') then
    return
  end

  local res = { header }
  list_extend(res, block)

  -- filter arguments beginning with '_'
  params = vim.tbl_filter(
    --- @param v {[1]: string, [2]: string, [3]: string[]}
    --- @return boolean
    function(v)
      return not startswith(v[1], '_')
    end,
    params
  )

  if #params > 0 then
    local param_block = { 'Parameters: ~' }

    local name_pad = 0
    for _, v in ipairs(params) do
      if #v[1] > name_pad then
        name_pad = #v[1]
      end
    end

    for _, v in ipairs(params) do
      local name, ty, desc = v[1], v[2], v[3]
      list_extend(param_block, render_param_or_return(name, ty, desc, name_pad))
    end
    list_extend(res, pad(param_block, 16))
  end

  if #returns > 0 then
    res[#res + 1] = ''
    local param_block = { 'Returns: ~' }
    for _, v in ipairs(returns) do
      local name, ty, desc = v[1], v[2], v[3]
      list_extend(param_block, render_param_or_return(name, ty, desc))
    end
    list_extend(res, pad(param_block, 16))
  end

  return res
end

--- @param path string
--- @return string
local function gen_functions_doc_from_file(path)
  local i = read_file(path):gmatch('([^\n]*)\n?') --- @type Iterator[string]

  local blocks = {} --- @type string[][]

  --- @alias EmmyState 'none'|'in_block'|'in_param'|'in_return'
  local state = 'none' --- @type EmmyState
  local desc = {} --- @type string[]
  local params = {} --- @type {[1]: string, [2]: string, [3]: string[]}[]
  local returns = {} --- @type {[1]: string, [2]: string, [3]: string[]}[]

  for l in i do
    local doc_comment = l:match('^%-%-%- ?(.*)') --- @type string?
    if doc_comment then
      state = process_doc_comment(state, doc_comment, desc, params, returns)
    elseif state ~= 'none' then
      -- First line after block
      local ok, header = pcall(parse_func_header, l)
      if ok then
        blocks[#blocks + 1] = render_block(header, desc, params, returns)
      end
      state = 'none'
      desc = {}
      params = {}
      returns = {}
    end
  end

  local res = {} --- @type string[]
  for j = #blocks, 1, -1 do
    local b = blocks[j]
    for k = 1, #b do
      res[#res + 1] = b[k]:match('^ *$') and '' or b[k]
    end
    res[#res + 1] = ''
  end

  return table.concat(res, '\n')
end

--- @param files string[]
--- @return string
local function gen_functions_doc(files)
  local res = {} --- @type string[]
  for _, path in ipairs(files) do
    res[#res + 1] = gen_functions_doc_from_file(path)
  end
  return table.concat(res, '\n')
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
        res[#res + 1] = string.format('%s*hl-%s*', string.rep(' ', 56), name)
        res[#res + 1] = string.format('%s', name)
        if spec.desc then
          res[#res + 1] = string.format('%s%s', string.rep(' ', 8), spec.desc)
          res[#res + 1] = ''
        end
        res[#res + 1] = string.format('%sFallbacks: %s', string.rep(' ', 8), fallbacks)
      end
    end
  end

  return table.concat(res, '\n')
end

--- @return string
local function get_setup_from_readme()
  local readme = read_file('README.md'):gmatch('([^\n]*)\n?') --- @type Iterator
  local res = {} --- @type string[]

  local function append(line)
    res[#res + 1] = line ~= '' and '    ' .. line or ''
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
    VERSION = '0.7-dev',
    CONFIG = gen_config_doc,
    FUNCTIONS = function()
      return gen_functions_doc({
        'lua/gitsigns.lua',
        'lua/gitsigns/attach.lua',
        'lua/gitsigns/actions.lua',
      })
    end,
    HIGHLIGHTS = gen_highlights_doc,
    SETUP = get_setup_from_readme,
  })[marker]
end

local function main()
  local template = read_file('etc/doc_template.txt'):gmatch('([^\n]*)\n?') --- @type Iterator

  local out = assert(io.open('doc/gitsigns.txt', 'w'))

  for l in template do
    local marker = l:match('{{(.*)}}')
    if marker then
      local sub = get_marker_text(marker)
      if sub then
        if type(sub) == 'function' then
          sub = sub()
        end
        sub = sub:gsub('%%', '%%%%')
        l = l:gsub('{{' .. marker .. '}}', sub)
      end
    end
    out:write(l or '', '\n')
  end
end

main()
