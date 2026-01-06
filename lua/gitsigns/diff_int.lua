local async = require('gitsigns.async')
local uv = vim.uv or vim.loop ---@diagnostic disable-line: deprecated

local create_hunk = require('gitsigns.hunks').create_hunk
local config = require('gitsigns.config').config

--- @return fun(v:any): string encode
--- @return fun(v:string): any decode
local function getencdec()
  local m = jit and package.preload['string.buffer'] and require('string.buffer') or vim.mpack
  --- @diagnostic disable-next-line: need-check-nil, undefined-field, return-type-mismatch
  --- EmmyLuaLs/emmylua-analyzer-rust#697
  return m.encode, m.decode
end

--- @async
--- @generic T, R
--- @param f fun(...:T...): R...
--- @param ... T...
--- @return R...
local function new_thread(f, ...)
  local args = { ... } --- @type T[]
  return async.await(1, function(cb)
    local encode, decode = getencdec()
    local worker = uv.new_work(function(getencdec_bc, f_bc, argse)
      local getencdec0 = getencdec or assert(loadstring(getencdec_bc --[[@as string]]))
      local encode0, decode0 = getencdec0()
      local args0 = decode0(argse) --[[@as any[] ]]
      local f0 = assert(loadstring(f_bc))
      return encode0(f0(unpack(args0)))
    end, function(r)
      cb(decode(r --[[@as string]]))
    end)

    local getencdec_bc = string.dump(getencdec)
    local f_bc = string.dump(f)
    worker:queue(getencdec_bc, f_bc, encode(args))
  end)
end

local M = {}

--- @alias Gitsigns.Region [integer, string, integer, integer]
--- @alias Gitsigns.RawHunk [integer, integer, integer, integer]

---@param a string
---@param b string
---@param opts Gitsigns.DiffOpts
---@param linematch? boolean
---@return Gitsigns.RawHunk[]
local function run_diff(a, b, opts, linematch)
  local linematch0 --- @type integer?
  if linematch ~= false then
    linematch0 = opts.linematch
  end
  --- @diagnostic disable-next-line: deprecated
  return (vim.text and vim.text.diff or vim.diff)(a, b, {
    result_type = 'indices',
    algorithm = opts.algorithm,
    indent_heuristic = opts.indent_heuristic,
    ignore_whitespace = opts.ignore_whitespace,
    ignore_whitespace_change = opts.ignore_whitespace_change,
    ignore_whitespace_change_at_eol = opts.ignore_whitespace_change_at_eol,
    ignore_blank_lines = opts.ignore_blank_lines,
    linematch = linematch0,
  }) --[[@as Gitsigns.RawHunk[] ]]
end

--- @async
--- @param a string
--- @param b string
--- @param opts Gitsigns.DiffOpts
--- @param linematch? boolean
--- @return Gitsigns.RawHunk[]
local function run_diff_async(a, b, opts, linematch)
  return new_thread(run_diff, a, b, opts, linematch)
end

--- @param fa string[]
--- @param fb string[]
--- @param rawhunks Gitsigns.RawHunk[]
--- @return Gitsigns.Hunk.Hunk[]
local function tohunks(fa, fb, rawhunks)
  local hunks = {} --- @type Gitsigns.Hunk.Hunk[]
  for _, r in ipairs(rawhunks) do
    local rs, rc, as, ac = r[1], r[2], r[3], r[4]
    local hunk = create_hunk(rs, rc, as, ac)
    if rc > 0 then
      for i = rs, rs + rc - 1 do
        hunk.removed.lines[#hunk.removed.lines + 1] = fa[i] or ''
      end
      if rs + rc >= #fa and fa[#fa] ~= '' then
        hunk.removed.no_nl_at_eof = true
      end
    end
    if ac > 0 then
      for i = as, as + ac - 1 do
        hunk.added.lines[#hunk.added.lines + 1] = fb[i] or ''
      end
      if as + ac >= #fb and fb[#fb] ~= '' then
        hunk.added.no_nl_at_eof = true
      end
    end
    hunks[#hunks + 1] = hunk
  end

  return hunks
end

--- @async
--- @param fa string[]
--- @param fb string[]
--- @param linematch? boolean
--- @return Gitsigns.Hunk.Hunk[]
function M.run_diff(fa, fb, linematch)
  local run_diff0 = config._threaded_diff and vim.is_thread and run_diff_async or run_diff
  local a = table.concat(fa, '\n')
  local b = table.concat(fb, '\n')
  return tohunks(fa, fb, run_diff0(a, b, config.diff_opts, linematch))
end

local gaps_between_regions = 5

--- @param hunks Gitsigns.Hunk.Hunk[]
--- @return Gitsigns.Hunk.Hunk[]
local function denoise_hunks(hunks)
  ---@diagnostic disable-next-line: assign-type-mismatch
  -- Denoise the hunks
  local ret = { hunks[1] }
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
    local rmd = removed[i] --- @cast rmd -?
    local add = added[i] --- @cast add -?

    -- pair lines by position
    local a = table.concat(vim.split(rmd, ''), '\n')
    local b = table.concat(vim.split(add, ''), '\n')

    local hunks = {} --- @type Gitsigns.Hunk.Hunk[]
    for _, r in ipairs(run_diff(a, b, config.diff_opts)) do
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
