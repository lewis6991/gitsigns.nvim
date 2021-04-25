#!/bin/sh
_=[[
exec lua "$0" "$@"
]]
-- Simple script to update the help doc by reading the config schema.

local function insert(t, s, ...)
  table.insert(t, s:format(...))
end

local function out(line, ...)
  io.write(line:format(...) or '', '\n')
end

local function mk_t(p, n)
  local tstr = {}
  for j = 1, n do
    table.insert(tstr, p..j)
  end
  return table.concat(tstr, ',')
end

local function l(x)
  if x == '' then
    return ''
  end
  return '<'..x..'>'
end

local function opt_paren(t)
  if t == '' then return '()' end
  return t
end

local function sfx(a, b)
  if b == 0 then return a end
  return a..'_'..b
end

local function main()
  io.output("teal/gitsigns/async.tl")

  out('local a = require(\'plenary.async_lib.async\')')
  out('')
  out('local record M')

  local futures    = {}
  local await_decs = {}
  local async_funs = {}
  local async_decs = {}
  local wrap_decs  = {}
  local await_imps = {}
  local wrap_imps  = {}
  local async_imps = {}

  for i = 0, 4 do
    local ti = mk_t('A', i)
    local oti = opt_paren(ti)
    local lti = l(ti)
    local future = 'future'..i
    local future_t = future..lti
    insert(futures, '  type %s = function%s(function(%s))', future, lti, ti)
    insert(await_decs, '  await%s: function%s(%s): %s', i, lti, future_t, oti)
    insert(await_imps, 'M.await%s = a.await as function%s(M.%s): %s', i, lti, future_t, oti)
    for j = 0, 4 do
      local tj = mk_t('R', j)
      local otj = opt_paren(tj)
      local tij = {}
      if ti ~= '' then table.insert(tij, ti) end
      if tj ~= '' then table.insert(tij, tj) end
      tij = table.concat(tij, ',')

      local sij = sfx(i,j)
      local ltij = l(tij)
      local ltj = l(tj)

      local tij2 = {}
      if ti ~= '' then table.insert(tij2, ti) end
      table.insert(tij2, 'function('..tj..')')
      tij2 = table.concat(tij2, ',')

      local async_name = 'async_fun'..sij
      local async_name_t = async_name..ltij

      insert(async_funs, '  type %s = function%s(%s): future%s%s', async_name, ltij, ti, j, ltj)
      insert(wrap_decs , '  wrap%s: function%s(function(%s)): %s', sij, ltij, tij2, async_name_t)
      insert(async_decs, '  async%s: function%s(function(%s): %s): %s', sij, ltij, ti, otj, async_name_t)
      insert(wrap_imps , 'M.wrap%s = function%s(func: function(%s)): M.%s', sij, ltij, tij2, async_name_t)
      insert(wrap_imps , '  return a.wrap(func, %s) as M.%s', i+1, async_name_t)
      insert(wrap_imps , 'end')
      insert(async_imps, 'M.async%s = a.async as function%s(function(%s): %s): M.%s', sij, ltij, ti, otj, async_name_t)
    end
  end

  insert(await_decs, '  await_main: function()')
  insert(await_imps, 'M.await_main = function()')
  insert(await_imps, '  a.await(a.scheduler())')
  insert(await_imps, 'end')

  for _, i in ipairs(futures)    do out(i) end out''
  for _, i in ipairs(await_decs) do out(i) end out''
  for _, i in ipairs(async_funs) do out(i) end out''
  for _, i in ipairs(wrap_decs)  do out(i) end out''
  for _, i in ipairs(async_decs) do out(i) end out''
  out'  void: function(function): function'
  out'  void_async: function(function): function'

  out''
  out'end'
  out''
  out'M.void = a.void'
  out'M.void_async = function(func: function): function'
  out'  return M.void(a.async(func))'
  out'end'
  out''

  for _, i in ipairs(await_imps) do out(i) end out''
  for _, i in ipairs(wrap_imps)  do out(i) end out''
  for _, i in ipairs(async_imps) do out(i) end out''

  out('return M')
end

main()
