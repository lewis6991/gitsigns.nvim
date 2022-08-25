local ffi = require("ffi")

ffi.cdef([[
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
]])







local function setup_mmbuffer(lines)
   local text = vim.tbl_isempty(lines) and '' or table.concat(lines, '\n') .. '\n'
   return text, #text
end









local function get_xpparam_flag(diff_algo)
   local daflag = 0

   if diff_algo == 'minimal' then daflag = 1
   elseif diff_algo == 'patience' then daflag = math.floor(2 ^ 14)
   elseif diff_algo == 'histogram' then daflag = math.floor(2 ^ 15)
   end

   return daflag
end

























local mmba = ffi.new('mmbuffer_t')
local mmbb = ffi.new('mmbuffer_t')
local xpparam = ffi.new('xpparam_t')
local emitcb = ffi.new('xdemitcb_t')

local function run_diff_xdl(fa, fb, diff_algo)
   mmba.ptr, mmba.size = setup_mmbuffer(fa)
   mmbb.ptr, mmbb.size = setup_mmbuffer(fb)
   xpparam.flags = get_xpparam_flag(diff_algo)

   local results = {}

   local hunk_func = ffi.cast('xdl_emit_hunk_consume_func_t', function(
      start_a, count_a, start_b, count_b)

      local ca = tonumber(count_a)
      local cb = tonumber(count_b)
      local sa = tonumber(start_a)
      local sb = tonumber(start_b)



      if ca > 0 then sa = sa + 1 end
      if cb > 0 then sb = sb + 1 end

      results[#results + 1] = { sa, ca, sb, cb }
      return 0
   end)

   local emitconf = ffi.new('xdemitconf_t')
   emitconf.hunk_func = hunk_func

   local ok = ffi.C.xdl_diff(mmba, mmbb, xpparam, emitconf, emitcb)

   hunk_func:free()

   return ok == 0 and results
end

jit.off(run_diff_xdl)

return run_diff_xdl
