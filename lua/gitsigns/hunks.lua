
local M = {}

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
      hunk.type = "delete"
   elseif removed.count == 0 then

      hunk.dend = added.start + added.count - 1
      hunk.type = "add"
   else

      hunk.dend = added.start + math.min(added.count, removed.count) - 1
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
   tonumber(pre[1]), tonumber(pre[2]) or 1,
   tonumber(now[1]), tonumber(now[2]) or 1)

   hunk.head = line

   return hunk
end

function M.get_range(hunk)
   local dend = hunk.dend
   if hunk.type == "change" then
      local add, remove = hunk.added.count, hunk.removed.count
      if add > remove then
         dend = dend + add - remove
      end
   end
   return hunk.start, dend
end

function M.process_hunks(hunks)
   local signs = {}
   for _, hunk in ipairs(hunks) do
      for i = hunk.start, hunk.dend do
         local topdelete = hunk.type == 'delete' and i == 0
         local changedelete = hunk.type == 'change' and hunk.removed.count > hunk.added.count and i == hunk.dend
         local count = hunk.type == 'add' and hunk.added.count or hunk.removed.count
         table.insert(signs, {
            type = topdelete and 'topdelete' or changedelete and 'changedelete' or hunk.type,
            lnum = topdelete and 1 or i,
            count = i == hunk.start and count,
         })
      end
      if hunk.type == "change" then
         local add, remove = hunk.added.count, hunk.removed.count
         if add > remove then
            local count = add - remove
            for i = 1, count do
               table.insert(signs, {
                  type = 'add',
                  lnum = hunk.dend + i,
                  count = i == 1 and count,
               })
            end
         end
      end
   end

   return signs
end

function M.create_patch(relpath, hunk, mode_bits, invert)
   invert = invert or false

   local start, pre_count, now_count = 
   hunk.removed.start, hunk.removed.count, hunk.added.count

   if hunk.type == 'add' then
      start = start + 1
   end

   local lines = hunk.lines

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

   return {
      string.format('diff --git a/%s b/%s', relpath, relpath),
      'index 000000..000000 ' .. mode_bits,
      '--- a/' .. relpath,
      '+++ b/' .. relpath,
      string.format('@@ -%s,%s +%s,%s @@', start, pre_count, start, now_count),
      unpack(lines),
   }
end

function M.get_summary(hunks)
   local status = { added = 0, changed = 0, removed = 0 }

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
      if lnum == 1 and hunk.start == 0 and hunk.dend == 0 then
         return hunk
      end

      local start, dend = M.get_range(hunk)

      if start <= lnum and dend >= lnum then
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
         if hunk.dend < lnum then
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
