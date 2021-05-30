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

local function out(line)
  io.write(line or '', '\n')
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
      if l:match('},') or l:match('nil,') then
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

local function intro()
  out[[
This section describes the configuration fields which can be passed to
|gitsigns.setup()|. Note fields of type `table` may be marked with extended
meaning the field is merged with the default, with the user value given higher
precedence. This allows only specific sub-fields to be configured without
having to redefine the whole field.
]]
end

local function gen_config_doc()
  intro()
  for _, k in ipairs(get_ordered_schema_keys()) do
    local v = config.schema[k]
    local t = ('*gitsigns-config-%s*'):format(k)
    out(('%-30s%48s'):format(k, t))

    local d
    if v.default_help ~= nil then
      d = v.default_help
    elseif is_simple_type(v.type) then
      d = inspect(v.default)
      d = ('`%s`'):format(d)
    else
      d = get_default(k)
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

local function main()
  local i = read_file('doc/gitsigns.txt'):gmatch("([^\n]*)\n?")

  io.output("doc/gitsigns.txt")

  -- Output doc upto config
  for l in i do
    out(l)
    if startswith(l, 'CONFIGURATION') then
      out()
      break
    end
  end

  -- Output new doc
  gen_config_doc()

  -- Skip over old doc
  for l in i do
    if startswith(l, '===================') then
      out(l)
      break
    end
  end

  -- Output remaining config
  for l in i do
    out(l)
  end
end

main()
