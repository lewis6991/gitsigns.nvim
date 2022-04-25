local Sign = require('gitsigns.signs').Sign
local StatusObj = require('gitsigns.status').StatusObj

local util = require('gitsigns.util')

local min, max = math.min, math.max

local M = {Node = {}, Hunk = {}, Hunk_Public = {}, }






























local Hunk = M.Hunk

function M.create_hunk(old_start, old_count, new_start, new_count)
   return {
      removed = { start = old_start, count = old_count, lines = {} },
      added = { start = new_start, count = new_count, lines = {} },
      head = ('@@ -%d%s +%d%s @@'):format(
      old_start, old_count > 0 and ',' .. old_count or '',
      new_start, new_count > 0 and ',' .. new_count or ''),

      vend = new_start + math.max(new_count - 1, 0),
      type = new_count == 0 and 'delete' or
      old_count == 0 and 'add' or
      'change',
   }
end

function M.create_partial_hunk(hunks, top, bot)
   local pretop, precount = top, bot - top + 1
   for _, h in ipairs(hunks) do
      local added_in_hunk = h.added.count - h.removed.count

      local added_in_range = 0
      if h.added.start >= top and h.vend <= bot then

         added_in_range = added_in_hunk
      else
         local added_above_bot = max(0, bot + 1 - (h.added.start + h.removed.count))
         local added_above_top = max(0, top - (h.added.start + h.removed.count))

         if h.added.start >= top and h.added.start <= bot then

            added_in_range = added_above_bot
         elseif h.vend >= top and h.vend <= bot then

            added_in_range = added_in_hunk - added_above_top
            pretop = pretop - added_above_top
         elseif h.added.start <= top and h.vend >= bot then

            added_in_range = added_above_bot - added_above_top
            pretop = pretop - added_above_top
         end

         if top > h.vend then
            pretop = pretop - added_in_hunk
         end
      end

      precount = precount - added_in_range
   end

   if precount == 0 then
      pretop = pretop - 1
   end

   return M.create_hunk(pretop, precount, top, bot - top + 1)
end

function M.patch_lines(hunk, fileformat)
   local lines = {}
   for _, l in ipairs(hunk.removed.lines) do
      lines[#lines + 1] = '-' .. l
   end
   for _, l in ipairs(hunk.added.lines) do
      lines[#lines + 1] = '+' .. l
   end

   if fileformat == 'dos' then
      lines = util.strip_cr(lines)
   end
   return lines
end

function M.parse_diff_line(line)
   local diffkey = vim.trim(vim.split(line, '@@', true)[2])



   local pre, now = unpack(vim.tbl_map(function(s)
      return vim.split(string.sub(s, 2), ',')
   end, vim.split(diffkey, ' ')))

   local hunk = M.create_hunk(
   tonumber(pre[1]), (tonumber(pre[2]) or 1),
   tonumber(now[1]), (tonumber(now[2]) or 1))

   hunk.head = line

   return hunk
end

local function change_end(hunk)
   if hunk.added.count == 0 then

      return hunk.added.start
   elseif hunk.removed.count == 0 then

      return hunk.added.start + hunk.added.count - 1
   else

      return hunk.added.start + min(hunk.added.count, hunk.removed.count) - 1
   end
end


function M.calc_signs(hunk, min_lnum, max_lnum)
   local start, added, removed = hunk.added.start, hunk.added.count, hunk.removed.count

   if hunk.type == 'delete' and start == 0 then
      if min_lnum <= 1 then

         return { { type = 'topdelete', count = removed, lnum = 1 } }
      else
         return {}
      end
   end

   local signs = {}

   local cend = change_end(hunk)

   for lnum = max(start, min_lnum), min(cend, max_lnum) do
      local changedelete = hunk.type == 'change' and removed > added and lnum == cend

      signs[#signs + 1] = {
         type = changedelete and 'changedelete' or hunk.type,
         count = lnum == start and (hunk.type == 'add' and added or removed),
         lnum = lnum,
      }
   end

   if hunk.type == "change" and added > removed and
      hunk.vend >= min_lnum and cend <= max_lnum then
      for lnum = max(cend, min_lnum), min(hunk.vend, max_lnum) do
         signs[#signs + 1] = {
            type = 'add',
            count = lnum == hunk.vend and (added - removed),
            lnum = lnum,
         }
      end
   end

   return signs
end

function M.create_patch(relpath, hunks, mode_bits, invert)
   invert = invert or false

   local results = {
      string.format('diff --git a/%s b/%s', relpath, relpath),
      'index 000000..000000 ' .. mode_bits,
      '--- a/' .. relpath,
      '+++ b/' .. relpath,
   }

   local offset = 0

   for _, process_hunk in ipairs(hunks) do
      local start, pre_count, now_count = 
      process_hunk.removed.start, process_hunk.removed.count, process_hunk.added.count

      if process_hunk.type == 'add' then
         start = start + 1
      end

      local pre_lines = process_hunk.removed.lines
      local now_lines = process_hunk.added.lines

      if invert then
         pre_count, now_count = now_count, pre_count
         pre_lines, now_lines = now_lines, pre_lines
      end

      table.insert(results, string.format('@@ -%s,%s +%s,%s @@', start, pre_count, start + offset, now_count))
      for _, l in ipairs(pre_lines) do
         results[#results + 1] = '-' .. l
      end
      for _, l in ipairs(now_lines) do
         results[#results + 1] = '+' .. l
      end

      process_hunk.removed.start = start + offset
      offset = offset + (now_count - pre_count)
   end

   return results
end

function M.get_summary(hunks)
   local status = { added = 0, changed = 0, removed = 0 }

   for _, hunk in ipairs(hunks or {}) do
      if hunk.type == 'add' then
         status.added = status.added + hunk.added.count
      elseif hunk.type == 'delete' then
         status.removed = status.removed + hunk.removed.count
      elseif hunk.type == 'change' then
         local add, remove = hunk.added.count, hunk.removed.count
         local delta = min(add, remove)
         status.changed = status.changed + delta
         status.added = status.added + add - delta
         status.removed = status.removed + remove - delta
      end
   end

   return status
end

function M.find_hunk(lnum, hunks)
   for i, hunk in ipairs(hunks) do
      if lnum == 1 and hunk.added.start == 0 and hunk.vend == 0 then
         return hunk, i
      end

      if hunk.added.start <= lnum and hunk.vend >= lnum then
         return hunk, i
      end
   end
end

function M.find_nearest_hunk(lnum, hunks, forwards, wrap)
   local ret
   local index
   if forwards then
      for i = 1, #hunks do
         local hunk = hunks[i]
         if hunk.added.start > lnum then
            ret = hunk
            index = i
            break
         end
      end
   else
      for i = #hunks, 1, -1 do
         local hunk = hunks[i]
         if hunk.vend < lnum then
            ret = hunk
            index = i
            break
         end
      end
   end
   if not ret and wrap then
      index = forwards and 1 or #hunks
      ret = hunks[index]
   end
   return ret, index
end

function M.compare_heads(a, b)
   if (a == nil) ~= (b == nil) then
      return true
   elseif a and #a ~= #b then
      return true
   end
   for i, ah in ipairs(a or {}) do
      if b[i].head ~= ah.head then
         return true
      end
   end
   return false
end

return M
