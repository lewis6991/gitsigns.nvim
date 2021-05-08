local create_hunk = require("gitsigns.hunks").create_hunk
local Hunk = require('gitsigns.hunks').Hunk

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
   local text = vim.tbl_isempty(lines) and '' or table.concat(lines, '\n') .. '\n'
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

   local jit_status = jit.status()



   jit.off()

   local hunk_func = ffi.cast('xdl_emit_hunk_consume_func_t', function(
      start_a, count_a, start_b, count_b)

      local ca = tonumber(count_a)
      local cb = tonumber(count_b)
      local sa = tonumber(start_a)
      local sb = tonumber(start_b)



      if ca > 0 then sa = sa + 1 end
      if cb > 0 then sb = sb + 1 end

      table.insert(results, { sa, ca, sb, cb })
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

   if jit_status then
      jit.on()
   end

   local hunks = {}

   for _, r in ipairs(results) do
      local rs, rc, as, ac = unpack(r)
      local hunk = create_hunk(rs, rc, as, ac)
      hunk.head = ('@@ -%d%s +%d%s @@'):format(
      rs, rc > 0 and ',' .. rc or '',
      as, ac > 0 and ',' .. ac or '')

      if rc > 0 then
         for i = rs, rs + rc - 1 do
            table.insert(hunk.lines, '-' .. (fa[i] or ''))
         end
      end
      if ac > 0 then
         for i = as, as + ac - 1 do
            table.insert(hunk.lines, '+' .. (fb[i] or ''))
         end
      end
      table.insert(hunks, hunk)
   end

   return hunks
end

return M
