local config = require('gitsigns.config').config

--- @alias Gitsigns.Difffn fun(fa: string[], fb: string[], algorithm?: string, indent_heuristic?: boolean, linematch?: integer): Gitsigns.Hunk.Hunk[]

--- @param a string[]
--- @param b string[]
--- @param linematch? boolean
--- @return Gitsigns.Hunk.Hunk[] hunks
return function(a, b, linematch)
  local diff_opts = config.diff_opts
  local f --- @type Gitsigns.Difffn
  if diff_opts.internal then
    f = require('gitsigns.diff_int').run_diff
  else
    f = require('gitsigns.diff_ext').run_diff
  end

  local linematch0 --- @type integer?
  if linematch ~= false then
    linematch0 = diff_opts.linematch
  end
  return f(a, b, diff_opts.algorithm, diff_opts.indent_heuristic, linematch0)
end
