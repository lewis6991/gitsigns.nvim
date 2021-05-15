local create_hunk = require("gitsigns.hunks").create_hunk
local Hunk        = require('gitsigns.hunks').Hunk

local ffi = require("ffi")

ffi.cdef[[
  typedef struct s_mmbuffer { const char *ptr; long size; } mmbuffer_t;

  typedef struct s_xpparam {
    unsigned long flags;

    // See Documentation/diff-options.txt.
    char **anchors;
    size_t anchors_nr;
  } xpparam_t;

  typedef long (__stdcall *find_func_t)(
    const char *line,
    long line_len,
    char *buffer,
    long buffer_size,
    void *priv
  );

  typedef int (__stdcall *xdl_emit_hunk_consume_func_t)(
    long start_a, long count_a, long start_b, long count_b,
    void *cb_data
  );

  typedef struct s_xdemitconf {
    long ctxlen;
    long interhunkctxlen;
    unsigned long flags;
    find_func_t find_func;
    void *find_func_priv;
    xdl_emit_hunk_consume_func_t hunk_func;
  } xdemitconf_t;

  typedef struct s_xdemitcb {
    void *priv;
    int (__stdcall *outf)(void *, mmbuffer_t *, int);
  } xdemitcb_t;

  int xdl_diff(
    mmbuffer_t *mf1,
    mmbuffer_t *mf2,
    xpparam_t const *xpp,
    xdemitconf_t const *xecfg,
    xdemitcb_t *ecb
  );
]]

local record MMBuffer
  userdata
  ptr: string
  size: number
end

local record XPParam
  userdata
  flags: number  -- unsigned long flags;

  -- char **anchors;
  -- size_t anchors_nr;
end

local function get_xpparam_flag(diff_algo: string): number
  local daflag = 0 -- myers

  if     diff_algo == 'minimal'   then daflag = 1
  elseif diff_algo == 'patience'  then daflag = math.floor(2^14)
  elseif diff_algo == 'histogram' then daflag = math.floor(2^15)
  end

  return daflag
end

local record Long
  userdata
end

local type XDLEmitHunkConsumeFunc = function(Long, Long, Long, Long, any): number

local type FindFunc = function(string, Long, integer, Long, any)

local record XDEmitConf
  userdata
  ctxlen: Long
  interhunkctxlen: Long
  flags: Long
  find_func: FindFunc -- find_func_t
  find_func_priv: any -- void *
  hunk_func: XDLEmitHunkConsumeFunc
end

local record XDEmitCB
  userdata
  priv: any
  outf: function(any, MMBuffer, integer)
end

local M = {}

local type DiffResult = {Long, Long, Long, Long}

local mmba     = ffi.new('mmbuffer_t')   as MMBuffer
local mmbb     = ffi.new('mmbuffer_t')   as MMBuffer
local xpparam  = ffi.new('xpparam_t')    as XPParam
local emitconf = ffi.new('xdemitconf_t') as XDEmitConf
local emitcb   = ffi.new('xdemitcb_t')   as XDEmitCB

local hunk_results: {DiffResult}

local hunk_func: XDLEmitHunkConsumeFunc = function(
  start_a: Long, count_a: Long, start_b: Long, count_b: Long, _
): number
  hunk_results[#hunk_results+1] = {start_a, count_a, start_b, count_b}
  return 0
end

local function run_diff_xdl(): {DiffResult}
  hunk_results = {}
  -- Need to recreate the cdata callback object in each call, otherwise the following
  -- assertion may trigger:
  --     LuaJIT ASSERT lj_ccallback.c:540: callback_conv_args: tvisfunc(...)
  local hf = ffi.cast('xdl_emit_hunk_consume_func_t', hunk_func)
  emitconf.hunk_func = hf as XDLEmitHunkConsumeFunc
  local ok = ffi.C.xdl_diff(mmba, mmbb, xpparam, emitconf, emitcb)
  hf:free() -- Allow the callback to be GC'd
  local results = hunk_results
  hunk_results = nil
  return ok == 0 and results
end

jit.off(run_diff_xdl)

function M.run_diff(fa: {string}, fb: {string}, diff_algo: string): {Hunk}
  local text_a = vim.tbl_isempty(fa) and '' or table.concat(fa, '\n')..'\n'
  local text_b = vim.tbl_isempty(fb) and '' or table.concat(fb, '\n')..'\n'
  mmba.ptr, mmba.size = text_a, #text_a
  mmbb.ptr, mmbb.size = text_b, #text_b
  xpparam.flags = get_xpparam_flag(diff_algo)

  local results = run_diff_xdl()

  local hunks: {Hunk} = {}

  for _, r in ipairs(results) do
    local rs0, rc0, as0, ac0 = unpack(r)
    local rs = tonumber(rs0) as integer
    local rc = tonumber(rc0) as integer
    local as = tonumber(as0) as integer
    local ac = tonumber(ac0) as integer

    -- Not fully sure why this offset is needed but xdiff does it too
    -- (see neovim/src/nvim/xdiff/xutils.c:356,368)
    if rc > 0 then rs = rs + 1 end
    if ac > 0 then as = as + 1 end

    local hunk = create_hunk(rs, rc, as, ac)
    hunk.head = ('@@ -%d%s +%d%s @@'):format(
      rs, rc > 0 and ','..rc or '',
      as, ac > 0 and ','..ac or ''
    )
    local lines: {string} = {}
    if rc > 0 then
      for i = rs, rs+rc-1 do
        lines[#lines+1] = '-'..(fa[i] or '')
      end
    end
    if ac > 0 then
      for i = as, as+ac-1 do
        lines[#lines+1] = '+'..(fb[i] or '')
      end
    end
    hunk.lines = lines
    hunks[#hunks+1] = hunk
  end

  return hunks
end

local type Region = {integer, string, integer, integer}

local gaps_between_regions = 5

function M.run_word_diff(hunk_body: {string}): {Region}
  local removed, added = 0, 0
  for _, line in ipairs(hunk_body) do
    if line:sub(1, 1) == '-' then
      removed = removed + 1
    elseif line:sub(1, 1) == '+' then
      added = added + 1
    end
  end

  if removed ~= added then
    return {}
  end

  local ret: {Region} = {}

  for i = 1, removed do
    -- pair lines by position
    local rline = hunk_body[i]:sub(2)
    local aline = hunk_body[i + removed]:sub(2)

    local a, b = vim.split(rline, ''), vim.split(aline, '')

    local hunks0: {Hunk} = {}
    for _, r in ipairs(run_diff_xdl(a, b)) do
      local rs, rc, as, ac = unpack(r)

      -- Balance of the unknown offset done in hunk_func
      if rc == 0 then rs = rs + 1 end
      if ac == 0 then as = as + 1 end

      -- print(string.format('-%d,%d +%d,%d', rs, rc, as, ac))
      hunks0[#hunks0+1] = create_hunk(rs, rc, as, ac)
    end

    -- Denoise the hunks
    local hunks = {hunks0[1]}
    for j = 2, #hunks0 do
      local h, n = hunks[#hunks], hunks0[j]
      if not h or not n then break end
      if n.added.start - h.added.start - h.added.count < gaps_between_regions  then
        h.added.count   = n.added.start   + n.added.count   - h.added.start
        h.removed.count = n.removed.start + n.removed.count - h.removed.start

        if h.added.count > 0 or h.removed.count > 0 then
          h.type = 'change'
        end
      else
        hunks[#hunks+1] = n
      end
    end

    for _, h in ipairs(hunks) do
      local rem = {i        , h.type, h.removed.start, h.removed.start + h.removed.count}
      local add = {i+removed, h.type, h.added.start  , h.added.start   + h.added.count}

      ret[#ret+1] = rem
      ret[#ret+1] = add
    end
  end
  return ret
end

return M
