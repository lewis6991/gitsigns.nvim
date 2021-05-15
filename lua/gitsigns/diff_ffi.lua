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





local XPParam = {}







local function get_xpparam_flag(diff_algo)
   local daflag = 0

   if diff_algo == 'minimal' then daflag = 1
   elseif diff_algo == 'patience' then daflag = math.floor(2 ^ 14)
   elseif diff_algo == 'histogram' then daflag = math.floor(2 ^ 15)
   end

   return daflag
end

local Long = {}



local XDLEmitHunkConsumeFunc = {}

local FindFunc = {}

local XDEmitConf = {}









local XDEmitCB = {}





local M = {}

local DiffResult = {}

local mmba = ffi.new('mmbuffer_t')
local mmbb = ffi.new('mmbuffer_t')
local xpparam = ffi.new('xpparam_t')
local emitconf = ffi.new('xdemitconf_t')
local emitcb = ffi.new('xdemitcb_t')

local hunk_results

local hunk_func = function(
   start_a, count_a, start_b, count_b, _)

   hunk_results[#hunk_results + 1] = { start_a, count_a, start_b, count_b }
   return 0
end

local function run_diff_xdl()
   hunk_results = {}



   local hf = ffi.cast('xdl_emit_hunk_consume_func_t', hunk_func)
   emitconf.hunk_func = hf
   local ok = ffi.C.xdl_diff(mmba, mmbb, xpparam, emitconf, emitcb)
   hf:free()
   local results = hunk_results
   hunk_results = nil
   return ok == 0 and results
end

jit.off(run_diff_xdl)

function M.run_diff(fa, fb, diff_algo)
   local text_a = vim.tbl_isempty(fa) and '' or table.concat(fa, '\n') .. '\n'
   local text_b = vim.tbl_isempty(fb) and '' or table.concat(fb, '\n') .. '\n'
   mmba.ptr, mmba.size = text_a, #text_a
   mmbb.ptr, mmbb.size = text_b, #text_b
   xpparam.flags = get_xpparam_flag(diff_algo)

   local results = run_diff_xdl()

   local hunks = {}

   for _, r in ipairs(results) do
      local rs0, rc0, as0, ac0 = unpack(r)
      local rs = tonumber(rs0)
      local rc = tonumber(rc0)
      local as = tonumber(as0)
      local ac = tonumber(ac0)



      if rc > 0 then rs = rs + 1 end
      if ac > 0 then as = as + 1 end

      local hunk = create_hunk(rs, rc, as, ac)
      hunk.head = ('@@ -%d%s +%d%s @@'):format(
      rs, rc > 0 and ',' .. rc or '',
      as, ac > 0 and ',' .. ac or '')

      local lines = {}
      if rc > 0 then
         for i = rs, rs + rc - 1 do
            lines[#lines + 1] = '-' .. (fa[i] or '')
         end
      end
      if ac > 0 then
         for i = as, as + ac - 1 do
            lines[#lines + 1] = '+' .. (fb[i] or '')
         end
      end
      hunk.lines = lines
      hunks[#hunks + 1] = hunk
   end

   return hunks
end

local Region = {}

local gaps_between_regions = 5

function M.run_word_diff(hunk_body)
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

   local ret = {}

   for i = 1, removed do

      local rline = hunk_body[i]:sub(2)
      local aline = hunk_body[i + removed]:sub(2)

      local a, b = vim.split(rline, ''), vim.split(aline, '')

      local hunks0 = {}
      for _, r in ipairs(run_diff_xdl(a, b)) do
         local rs, rc, as, ac = unpack(r)


         if rc == 0 then rs = rs + 1 end
         if ac == 0 then as = as + 1 end


         hunks0[#hunks0 + 1] = create_hunk(rs, rc, as, ac)
      end


      local hunks = { hunks0[1] }
      for j = 2, #hunks0 do
         local h, n = hunks[#hunks], hunks0[j]
         if not h or not n then break end
         if n.added.start - h.added.start - h.added.count < gaps_between_regions then
            h.added.count = n.added.start + n.added.count - h.added.start
            h.removed.count = n.removed.start + n.removed.count - h.removed.start

            if h.added.count > 0 or h.removed.count > 0 then
               h.type = 'change'
            end
         else
            hunks[#hunks + 1] = n
         end
      end

      for _, h in ipairs(hunks) do
         local rem = { i, h.type, h.removed.start, h.removed.start + h.removed.count }
         local add = { i + removed, h.type, h.added.start, h.added.start + h.added.count }

         ret[#ret + 1] = rem
         ret[#ret + 1] = add
      end
   end
   return ret
end

return M
