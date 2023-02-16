#!/bin/sh
_=[[
exec luajit "$0" "$@"
]]

local uv = require'luv'

local function read_file(path)
  local f = assert(io.open(path, 'r'))
  local t = f:read("*all")
  f:close()
  return t
end

local function join_paths(...)
  return table.concat({ ... }, '/'):gsub('//+', '/')
end

local function dir(path)
  --- @async
  return coroutine.wrap(function()
    local dirs = { { path, 1 } }
    while #dirs > 0 do
      local dir0, level = unpack(table.remove(dirs, 1))
      local dir1 = level == 1 and dir0 or join_paths(path, dir0)
      local fs = uv.fs_scandir(dir1)
      while fs do
        local name, t = uv.fs_scandir_next(fs)
        if not name then
          break
        end
        local f = level == 1 and name or join_paths(dir0, name)
        if t == 'directory' then
          dirs[#dirs + 1] = { f, level + 1 }
        else
          coroutine.yield(f, t)
        end
      end
    end
  end)
end

local function write_file(path, lines)
  local f = assert(io.open(path, 'w'))
  f:write(table.concat(lines, '\n'))
  f:close()
end

local function read_file_lines(path)
  local lines = {}
  for l in read_file(path):gmatch("([^\n]*)\n?") do
    table.insert(lines, l)
  end
  return lines
end

for p in dir('teal') do
  local path = join_paths('teal', p)
  local op = p:gsub('%.tl$', '.lua')
  local opath = join_paths('lua', op)

  local lines = read_file_lines(path)

  local comments = {}
  for i, l in ipairs(lines) do
    local comment = l:match('%s*%-%-.*')
    if comment then
      comments[i] = comment:gsub('  ', '   ')
    end
  end

  local olines = read_file_lines(opath)

  for i, l in pairs(comments) do
    if not olines[i]:match('%-%-.*') then
      olines[i] = olines[i]..l
    end
  end
  write_file(opath, olines)
end

