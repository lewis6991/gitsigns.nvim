local create_hunk = require("gitsigns/hunks").create_hunk

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

local MMBuffer = {}





local function mmbuffer(lines)
   local text = table.concat(lines, '\n') .. '\n'
   return ffi.new('mmbuffer_t', text, #text)
end

local XPParam = {}







local function xpparam(diff_algo)
   local daflag = 0

   if diff_algo == 'minimal' then daflag = 1
   elseif diff_algo == 'patience' then daflag = math.floor(2 ^ 14)
   elseif diff_algo == 'histogram' then daflag = math.floor(2 ^ 15)
   end

   return ffi.new('xpparam_t', daflag)
end

local Long = {}



local XDEmitConf = {}

















local M = {}

function M.run_diff(fa, fb, diff_algo)
   local results = {}

   local hunk_func = ffi.cast('xdl_emit_hunk_consume_func_t', function(
      start_a, count_a,
      start_b, count_b)

      table.insert(results, create_hunk(
      tonumber(start_a) + 1, tonumber(count_a),
      tonumber(start_b) + 1, tonumber(count_b)))


      return 0
   end)

   local emitconf = ffi.new('xdemitconf_t')
   emitconf.hunk_func = hunk_func

   local res = ffi.C.xdl_diff(
   mmbuffer(fa),
   mmbuffer(fb),
   xpparam(diff_algo),
   emitconf,
   ffi.new('xdemitcb_t'))


   assert(res, 'DIFF bad result')

   hunk_func:free()

   for _, hunk in ipairs(results) do
      hunk.head = ('@@ -%d,%d +%d,%d @@'):format(
      hunk.removed.start, hunk.removed.count,
      hunk.added.start, hunk.added.count)

      if hunk.removed.count > 0 then
         for i = hunk.removed.start, hunk.removed.start + hunk.removed.count - 1 do
            table.insert(hunk.lines, '-' .. (fa[i] or ''))
         end
      end
      if hunk.added.count > 0 then
         for i = hunk.added.start, hunk.added.start + hunk.added.count - 1 do
            table.insert(hunk.lines, '+' .. (fb[i] or ''))
         end
      end
   end

   return results
end

return M
