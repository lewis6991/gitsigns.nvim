local Sign = require('gitsigns.signs').Sign
local StatusObj = require('gitsigns.status').StatusObj

local M = {Node = {}, Hunk = {}, Hunk_Public = {}, }
































local Hunk = M.Hunk

function M.create_hunk(start_a, count_a, start_b, count_b)
   local removed = { start = start_a, count = count_a, lines = {} }
   local added = { start = start_b, count = count_b, lines = {} }

   local hunk = {
      start = added.start,
      removed = removed,
      added = added,
      head = ('@@ -%d%s +%d%s @@'):format(
      start_a, count_a > 0 and ',' .. count_a or '',
      start_b, count_b > 0 and ',' .. count_b or ''),

   }

   if added.count == 0 then

      hunk.dend = added.start
      hunk.vend = hunk.dend
      hunk.type = "delete"
   elseif removed.count == 0 then

      hunk.dend = added.start + added.count - 1
      hunk.vend = hunk.dend
      hunk.type = "add"
   else

      hunk.dend = added.start + math.min(added.count, removed.count) - 1
      hunk.vend = hunk.dend + math.max(added.count - removed.count, 0)
      hunk.type = "change"
   end

   return hunk
end

function M.create_partial_hunk(hunks, top, bot)
   local pretop, precount = top, bot - top + 1
   for _, h in ipairs(hunks) do
      local added_in_hunk = h.added.count - h.removed.count

      local added_in_range = 0
      if h.start >= top and h.vend <= bot then

         added_in_range = added_in_hunk
      else
         local added_above_bot = math.max(0, bot + 1 - (h.start + h.removed.count))
         local added_above_top = math.max(0, top - (h.start + h.removed.count))

         if h.start >= top and h.start <= bot then

            added_in_range = added_above_bot
         elseif h.vend >= top and h.vend <= bot then

            added_in_range = added_in_hunk - added_above_top
            pretop = pretop - added_above_top
         elseif h.start <= top and h.vend >= bot then

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

function M.patch_lines(hunk)
   local lines = {}
   for _, l in ipairs(hunk.removed.lines) do
      lines[#lines + 1] = '-' .. l
   end
   for _, l in ipairs(hunk.added.lines) do
      lines[#lines + 1] = '+' .. l
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

function M.process_hunks(hunks)
   local signs = {}
   for _, hunk in ipairs(hunks or {}) do
      local count = hunk.type == 'add' and hunk.added.count or hunk.removed.count
      for i = hunk.start, hunk.dend do
         local topdelete = hunk.type == 'delete' and i == 0
         local changedelete = hunk.type == 'change' and hunk.removed.count > hunk.added.count and i == hunk.dend

         signs[topdelete and 1 or i] = {
            type = topdelete and 'topdelete' or changedelete and 'changedelete' or hunk.type,
            count = i == hunk.start and count,
         }
      end
      if hunk.type == "change" then
         local add, remove = hunk.added.count, hunk.removed.count
         if add > remove then
            local count_diff = add - remove
            for i = 1, count_diff do
               signs[hunk.dend + i] = {
                  type = 'add',
                  count = i == 1 and count_diff,
               }
            end
         end
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
         local min = math.min(add, remove)
         status.changed = status.changed + min
         status.added = status.added + add - min
         status.removed = status.removed + remove - min
      end
   end

   return status
end

function M.find_hunk(lnum, hunks)
   for i, hunk in ipairs(hunks) do
      if lnum == 1 and hunk.start == 0 and hunk.vend == 0 then
         return hunk, i
      end

      if hunk.start <= lnum and hunk.vend >= lnum then
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
         if hunk.start > lnum then
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
