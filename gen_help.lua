#!/bin/sh
_=[[
exec lua "$0" "$@"
]]
-- Simple script to update the help doc by reading the config schema.

local inspect = require('inspect')
local config = require('lua/gitsigns/config')

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

-- To makw sure the output is consistent between runs (to minimise diffs), we
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

local function gen_config_doc()
  for _, k in ipairs(get_ordered_schema_keys()) do
    local v = config.schema[k]
    local t = ('*gitsigns-config-%s*'):format(k)
    out(('%-30s%48s'):format(k, t))
    if v.default_help ~= nil or is_simple_type(v.type) then
      local d = v.default_help or ('`%s`'):format(inspect(v.default))
      out(('        Type: `%s`, Default: %s'):format(v.type, d))
      out()
    else
      out(('        Type: `%s`, Default:'):format(v.type))
      out('>')
      local d = v.default
      if type(d) == 'table' then
        d = inspect(d):gsub('\n([^\n\r])', '\n    %1')
      elseif type(d) == 'function' then
        local info = debug.getinfo(d)
        local start, last = info.linedefined, info.lastlinedefined
        local source = info.source:sub(2)  -- Remove leading @
        local func = table.slice(read_file_lines(source), start, last)
        d = table.concat(func, '\n    ')
      end
      out('        '..d:gsub('\n([^\n\r])', '\n    %1'))
      out('<')
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
-- helo
