local M = {}

local gap_between_regions = 5


local function get_lcs(s1, s2)
   if s1 == '' or s2 == '' then
      return ''
   end

   local matrix = {}
   for i = 1, #s1 + 1 do
      matrix[i] = {}
      for j = 1, #s2 + 1 do
         matrix[i][j] = 0
      end
   end

   local maxlength = 0
   local endindex = #s1

   for i = 2, #s1 + 1 do
      for j = 2, #s2 + 1 do
         if s1:sub(i - 1, i - 1) == s2:sub(j - 1, j - 1) then
            matrix[i][j] = 1 + matrix[i - 1][j - 1]
            if matrix[i][j] > maxlength then
               maxlength = matrix[i][j]
               endindex = i
            end
         end
      end
   end

   return s1:sub(endindex - maxlength, endindex - 1)
end







local function common_prefix(a, b)
   local len = math.min(#a, #b)
   if len == 0 then
      return 0
   end
   for i = 1, len do
      if a:sub(i, i) ~= b:sub(i, i) then
         return i - 1
      end
   end
   return len
end







local function common_suffix(a, b, start)
   local sa, sb = #a, #b
   while sa >= start and sb >= start do
      if a:sub(sa, sa) == b:sub(sb, sb) then
         sa = sa - 1
         sb = sb - 1
      else
         break
      end
   end
   return sa, sb
end

local Region = {}

local function diff(rline, aline, rlinenr, alinenr, rprefix, aprefix, regions, whole_line)


   local start = whole_line and 2 or 1
   local prefix = common_prefix(rline:sub(start), aline:sub(start))
   if whole_line then
      prefix = prefix + 1
   end
   local rsuffix, asuffix = common_suffix(rline, aline, prefix + 1)


   local rtext = rline:sub(prefix + 1, rsuffix)
   local atext = aline:sub(prefix + 1, asuffix)








   if rtext == '' then
      if not whole_line or #atext ~= #aline then
         regions[#regions + 1] = { alinenr, '+', aprefix + prefix + 1, aprefix + asuffix }
      end
   end


   if atext == '' then
      if not whole_line or #rtext ~= #rline then
         regions[#regions + 1] = { rlinenr, '-', rprefix + prefix + 1, rprefix + rsuffix }
      end
   end

   if rtext == '' or atext == '' then
      return
   end


   local j = vim.fn.stridx(atext, rtext)
   if j ~= -1 then
      regions[#regions + 1] = { alinenr, '+', aprefix + prefix + 1, aprefix + prefix + j }
      regions[#regions + 1] = { alinenr, '+', aprefix + prefix + 1 + j + #rtext, aprefix + asuffix - 1 }
      return
   end


   local k = vim.fn.stridx(rtext, atext)
   if k ~= -1 then
      regions[#regions + 1] = { rlinenr, '-', rprefix + prefix + 1, rprefix + prefix + k }
      regions[#regions + 1] = { rlinenr, '-', rprefix + prefix + 1 + k + #atext, rprefix + rsuffix }
      return
   end


   local lcs = get_lcs(rtext, atext)



   if #lcs > gap_between_regions then
      local redits = vim.split(rtext, lcs, true)
      local aedits = vim.split(atext, lcs, true)

      diff(redits[1], aedits[1], rlinenr, alinenr, rprefix + prefix, aprefix + prefix, regions, false)

      diff(redits[2], aedits[2], rlinenr, alinenr, rprefix + prefix + #redits[1] + #lcs, aprefix + prefix + #aedits[1] + #lcs, regions, false)
      return
   end




   if not whole_line or ((prefix ~= 0 or rsuffix ~= #rline) and prefix + 1 < rsuffix) then
      regions[#regions + 1] = { rlinenr, '-', rprefix + prefix + 1, rprefix + rsuffix }
   end


   if not whole_line or ((prefix ~= 0 or asuffix ~= #aline) and prefix + 1 < asuffix) then
      regions[#regions + 1] = { alinenr, '+', aprefix + prefix + 1, aprefix + asuffix }
   end
end
























function M.process(hunk_body)

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

   local regions
   regions = {}









   for i = 1, removed do

      local rline = hunk_body[i]
      local aline = hunk_body[i + removed]

      diff(rline, aline, i, i + removed, 0, 0, regions, true)
   end

   return regions
end

return M
