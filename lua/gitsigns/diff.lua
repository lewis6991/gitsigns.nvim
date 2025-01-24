local config = require('gitsigns.config').config

--- @async
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

  if config.diff_opts.internal then
    return require('gitsigns.diff_int').run_diff(a, b, linematch)
  else
    return require('gitsigns.diff_ext').run_diff(a, b)
  end
end
