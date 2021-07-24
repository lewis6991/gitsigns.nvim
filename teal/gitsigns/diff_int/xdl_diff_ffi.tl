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
  ptr: number
  size: number
end

local function setup_mmbuffer(lines: {string}): number, number
  local text = vim.tbl_isempty(lines) and '' or table.concat(lines, '\n')..'\n'
  return text as number, #text
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

local record XDEmitConf
  userdata
  hunk_func: function(Long, Long, Long, Long, any): number
end

-- local DIFF_FILLER     = 0x001   -- display filler lines
-- local DIFF_IBLANK     = 0x002   -- ignore empty lines
-- local DIFF_ICASE      = 0x004   -- ignore case
-- local DIFF_IWHITE     = 0x008   -- ignore change in white space
-- local DIFF_IWHITEALL  = 0x010   -- ignore all white space changes
-- local DIFF_IWHITEEOL  = 0x020   -- ignore change in white space at EOL
-- local DIFF_HORIZONTAL = 0x040   -- horizontal splits
-- local DIFF_VERTICAL   = 0x080   -- vertical splits
-- local DIFF_HIDDEN_OFF = 0x100   -- diffoff when hidden
-- local DIFF_INTERNAL   = 0x200   -- use internal xdiff algorithm
-- local DIFF_CLOSE_OFF  = 0x400   -- diffoff when closing window
-- local DIFF_FOLLOWWRAP = 0x800   -- follow the wrap option

local type DiffResult = {integer, integer, integer, integer}

local mmba = ffi.new('mmbuffer_t') as MMBuffer
local mmbb = ffi.new('mmbuffer_t') as MMBuffer
local xpparam = ffi.new('xpparam_t') as XPParam
local emitcb = ffi.new('xdemitcb_t') as any

local function run_diff_xdl(fa: {string}, fb: {string}, diff_algo: string): {DiffResult}
  mmba.ptr, mmba.size = setup_mmbuffer(fa)
  mmbb.ptr, mmbb.size = setup_mmbuffer(fb)
  xpparam.flags = get_xpparam_flag(diff_algo)

  local results: {DiffResult} = {}

  local hunk_func = ffi.cast('xdl_emit_hunk_consume_func_t', function(
    start_a: Long, count_a: Long, start_b: Long, count_b: Long
  ): number
    local ca = tonumber(count_a) as integer
    local cb = tonumber(count_b) as integer
    local sa = tonumber(start_a) as integer
    local sb = tonumber(start_b) as integer

    -- Not fully sure why this offset is needed but xdiff does it too
    -- (see neovim/src/nvim/xdiff/xutils.c:356,368)
    if ca > 0 then sa = sa + 1 end
    if cb > 0 then sb = sb + 1 end

    results[#results+1] = {sa, ca, sb, cb}
    return 0
  end)

  local emitconf = ffi.new('xdemitconf_t') as XDEmitConf
  emitconf.hunk_func = hunk_func as function(Long, Long, Long, Long): integer

  local ok = ffi.C.xdl_diff(mmba, mmbb, xpparam, emitconf, emitcb)

  hunk_func:free()

  return ok == 0 and results
end

jit.off(run_diff_xdl)

return run_diff_xdl
