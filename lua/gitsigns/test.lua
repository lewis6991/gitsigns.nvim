local M = {}

local function eq(act, exp)
  assert(act == exp, string.format('%s != %s', act, exp))
end

M._tests = {}

M._tests.expand_format = function()
  local util = require('gitsigns.util')
  assert('hello % world % 2021' == util.expand_format('<var1> % <var2> % <var_time:%Y>', {
    var1 = 'hello',
    var2 = 'world',
    var_time = 1616838297,
  }))
end

M._tests.test_args = function()
  local parse_args = require('gitsigns.cli.argparse').parse_args

  local pos_args, named_args = parse_args('hello  there key=value, key1="a b c"')

  eq(pos_args[1], 'hello')
  eq(pos_args[2], 'there')
  eq(named_args.key, 'value,')
  eq(named_args.key1, 'a b c')

  pos_args, named_args = parse_args('base=HEAD~1 posarg')

  eq(named_args.base, 'HEAD~1')
  eq(pos_args[1], 'posarg')
end

return M
