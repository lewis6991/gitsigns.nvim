local create_hunk = require('gitsigns.hunks').create_hunk
local config = require('gitsigns.config').config
local async = require('gitsigns.async')

local M = {}

--- @alias Gitsigns.Region {[1]:integer, [2]:string, [3]:integer, [4]:integer}

--- @alias Gitsigns.RawHunk {[1]:integer, [2]:integer, [3]:integer, [4]:integer}
--- @alias Gitsigns.RawDifffn fun(a: string, b: string, linematch?: integer): Gitsigns.RawHunk[]

--- @type Gitsigns.RawDifffn
local run_diff_xdl = function(a, b, linematch)
  local opts = config.diff_opts
  return vim.diff(a, b, {
    result_type = 'indices',
    algorithm = opts.algorithm,
    indent_heuristic = opts.indent_heuristic,
    ignore_whitespace = opts.ignore_whitespace,
    ignore_whitespace_change = opts.ignore_whitespace_change,
    ignore_whitespace_change_at_eol = opts.ignore_whitespace_change_at_eol,
    ignore_blank_lines = opts.ignore_blank_lines,
    linematch = linematch,
  }) --[[@as Gitsigns.RawHunk[] ]]
end

--- @type Gitsigns.RawDifffn
local run_diff_xdl_async = async.wrap(
  --- @param a string
  --- @param b string
  --- @param linematch? integer
  --- @param callback fun(hunks: Gitsigns.RawHunk[])
  function(a, b, linematch, callback)
    local opts = config.diff_opts
    local function toflag(f, pos)
      return f and bit.lshift(1, pos) or 0
    end

    local flags = toflag(opts.indent_heuristic, 0)
      + toflag(opts.ignore_whitespace, 1)
      + toflag(opts.ignore_whitespace_change, 2)
      + toflag(opts.ignore_whitespace_change_at_eol, 3)
      + toflag(opts.ignore_blank_lines, 4)

    vim.loop
      .new_work(
        --- @param a0 string
        --- @param b0 string
        --- @param algorithm string
        --- @param flags0 integer
        --- @param linematch0 integer
        --- @return string
        function(a0, b0, algorithm, flags0, linematch0)
          local function flagval(pos)
            return bit.band(flags0, bit.lshift(1, pos)) ~= 0
          end

          --- @diagnostic disable-next-line:return-type-mismatch
          return vim.mpack.encode(vim.diff(a0, b0, {
            result_type = 'indices',
            algorithm = algorithm,
            linematch = linematch0,
            indent_heuristic = flagval(0),
            ignore_whitespace = flagval(1),
            ignore_whitespace_change = flagval(2),
            ignore_whitespace_change_at_eol = flagval(3),
            ignore_blank_lines = flagval(4),
          }))
        end,
        --- @param r string
        function(r)
          callback(vim.mpack.decode(r) --[[@as Gitsigns.RawHunk[] ]])
        end
      )
      :queue(a, b, opts.algorithm, flags, linematch)
  end,
  4
)

--- @param fa string[]
--- @param fb string[]
--- @param linematch? integer
--- @return Gitsigns.Hunk.Hunk[]
function M.run_diff(fa, fb, linematch)
  local run_diff0 --- @type Gitsigns.RawDifffn
  if config._threaded_diff and vim.is_thread then
    run_diff0 = run_diff_xdl_async
  else
    run_diff0 = run_diff_xdl
  end

  local a = table.concat(fa, '\n')
  local b = table.concat(fb, '\n')

  local results = run_diff0(a, b, linematch)

  local hunks = {} --- @type Gitsigns.Hunk.Hunk[]
  for _, r in ipairs(results) do
    local rs, rc, as, ac = r[1], r[2], r[3], r[4]
    local hunk = create_hunk(rs, rc, as, ac)
    if rc > 0 then
      for i = rs, rs + rc - 1 do
        hunk.removed.lines[#hunk.removed.lines + 1] = fa[i] or ''
      end
    end
    if ac > 0 then
      for i = as, as + ac - 1 do
        hunk.added.lines[#hunk.added.lines + 1] = fb[i] or ''
      end
    end
    hunks[#hunks + 1] = hunk
  end

  return hunks
end

local gaps_between_regions = 5

--- @param hunks Gitsigns.Hunk.Hunk[]
--- @return Gitsigns.Hunk.Hunk[]
local function denoise_hunks(hunks)
  -- Denoise the hunks
  local ret = { hunks[1] } --- @type Gitsigns.Hunk.Hunk[]
  for j = 2, #hunks do
    local h, n = ret[#ret], hunks[j]
    if not h or not n then
      break
    end
    if n.added.start - h.added.start - h.added.count < gaps_between_regions then
      h.added.count = n.added.start + n.added.count - h.added.start
      h.removed.count = n.removed.start + n.removed.count - h.removed.start

      if h.added.count > 0 or h.removed.count > 0 then
        h.type = 'change'
      end
    else
      ret[#ret + 1] = n
    end
  end
  return ret
end

--- @param removed string[]
--- @param added string[]
--- @return Gitsigns.Region[] removed
--- @return Gitsigns.Region[] added
function M.run_word_diff(removed, added)
  local adds = {} --- @type Gitsigns.Region[]
  local rems = {} --- @type Gitsigns.Region[]

  if #removed ~= #added then
    return rems, adds
  end

  for i = 1, #removed do
    -- pair lines by position
    local a = table.concat(vim.split(removed[i], ''), '\n')
    local b = table.concat(vim.split(added[i], ''), '\n')

    local hunks = {} --- @type Gitsigns.Hunk.Hunk[]
    for _, r in ipairs(run_diff_xdl(a, b)) do
      local rs, rc, as, ac = r[1], r[2], r[3], r[4]

      -- Balance of the unknown offset done in hunk_func
      if rc == 0 then
        rs = rs + 1
      end
      if ac == 0 then
        as = as + 1
      end

      hunks[#hunks + 1] = create_hunk(rs, rc, as, ac)
    end

    hunks = denoise_hunks(hunks)

    for _, h in ipairs(hunks) do
      adds[#adds + 1] = { i, h.type, h.added.start, h.added.start + h.added.count }
      rems[#rems + 1] = { i, h.type, h.removed.start, h.removed.start + h.removed.count }
    end
  end
  return rems, adds
end

return M
