local config = require('gitsigns.config').config

--- @alias Gitsigns.Difffn fun(fa: string[], fb: string[], linematch?: integer): Gitsigns.Hunk.Hunk[]

--- @param a string[]
--- @param b string[]
--- @param linematch? boolean
--- @return Gitsigns.Hunk.Hunk[] hunks
return function(a, b, linematch)
  -- -- Short circuit optimization
  -- if not a or #a == 0 then
  --   local Hunks = require('gitsigns.hunks')
  --   local hunk = Hunks.create_hunk(0, 0, 1, #b)
  --   hunk.added.lines = b
  --   return { hunk }
  -- end

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

  return f(a, b, linematch0)
end
