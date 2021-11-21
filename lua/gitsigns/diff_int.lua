local create_hunk = require("gitsigns.hunks").create_hunk
local Hunk = require('gitsigns.hunks').Hunk

local M = {}

local DiffResult = {}

local run_diff_xdl

if vim.diff then
   run_diff_xdl = function(fa, fb, algorithm, indent_heuristic)
      local a = vim.tbl_isempty(fa) and '' or table.concat(fa, '\n') .. '\n'
      local b = vim.tbl_isempty(fb) and '' or table.concat(fb, '\n') .. '\n'
      return vim.diff(a, b, {
         result_type = 'indices',
         algorithm = algorithm,
         indent_heuristic = indent_heuristic,
      })
   end
else
   run_diff_xdl = require('gitsigns.diff_int.xdl_diff_ffi')
end

function M.run_diff(fa, fb, diff_algo, indent_heuristic)
   local results = run_diff_xdl(fa, fb, diff_algo, indent_heuristic)

   local hunks = {}

   for _, r in ipairs(results) do
      local rs, rc, as, ac = unpack(r)
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

local Region = {}

local gaps_between_regions = 5

function M.run_word_diff(removed, added)
   if #removed ~= #added then
      return {}
   end

   local ret = {}

   for i = 1, #removed do

      local rline = removed[i]
      local aline = added[i]

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
         local add = { i + #removed, h.type, h.added.start, h.added.start + h.added.count }

         ret[#ret + 1] = rem
         ret[#ret + 1] = add
      end
   end
   return ret
end

return M
