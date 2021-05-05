local Sign = require('gitsigns.signs').Sign
local StatusObj = require('gitsigns.status').StatusObj

local M = {Hunk = {Node = {}, }, }
























local Hunk = M.Hunk

function M.create_hunk(start_a, count_a, start_b, count_b)
   local removed = { start = start_a, count = count_a }
   local added = { start = start_b, count = count_b }

   local hunk = {
      start = added.start,
      lines = {},
      removed = removed,
      added = added,
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
   for _, hunk in ipairs(hunks) do
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

      local lines = process_hunk.lines

      if invert then
         pre_count, now_count = now_count, pre_count

         lines = vim.tbl_map(function(l)
            if vim.startswith(l, '+') then
               l = '-' .. string.sub(l, 2, -1)
            elseif vim.startswith(l, '-') then
               l = '+' .. string.sub(l, 2, -1)
            end
            return l
         end, lines)
      end

      table.insert(results, string.format('@@ -%s,%s +%s,%s @@', start, pre_count, start + offset, now_count))
      for _, line in ipairs(lines) do
         table.insert(results, line)
      end

      process_hunk.removed.start = start + offset
      offset = offset + (now_count - pre_count)
   end

   return results
end

function M.get_summary(hunks, head)
   local status = { added = 0, changed = 0, removed = 0, head = head }

   for _, hunk in ipairs(hunks) do
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
   for _, hunk in ipairs(hunks) do
      if lnum == 1 and hunk.start == 0 and hunk.vend == 0 then
         return hunk
      end

      if hunk.start <= lnum and hunk.vend >= lnum then
         return hunk
      end
   end
end

function M.find_nearest_hunk(lnum, hunks, forwards, wrap)
   local ret
   if forwards then
      for i = 1, #hunks do
         local hunk = hunks[i]
         if hunk.start > lnum then
            ret = hunk
            break
         end
      end
   else
      for i = #hunks, 1, -1 do
         local hunk = hunks[i]
         if hunk.vend < lnum then
            ret = hunk
            break
         end
      end
   end
   if not ret and wrap then
      ret = hunks[forwards and 1 or #hunks]
   end
   return ret
end

function M.extract_removed(hunk)
   return vim.tbl_map(function(l)
      return string.sub(l, 2, -1)
   end, vim.tbl_filter(function(l)
      return vim.startswith(l, '-')
   end, hunk.lines))
end

return M
