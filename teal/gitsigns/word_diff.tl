local M = {}

local gap_between_regions = 5

-- get_lcs('hello', 'hheloooo') == 'hel'
local function get_lcs(s1: string, s2: string): string
  if s1 == '' or s2 == '' then
    return ''
  end

  local matrix: {{integer}} = {}
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
      if s1:sub(i-1, i-1) == s2:sub(j-1, j-1) then
        matrix[i][j] = 1 + matrix[i-1][j-1]
        if matrix[i][j] > maxlength then
          maxlength = matrix[i][j]
          endindex = i
        end
      end
    end
  end

  return s1:sub(endindex - maxlength, endindex - 1)
end

-- Returns 1-based index of last character of common prefix
-- If there is no common prefix, returns 0.
--
-- a, b - strings
--
-- common_prefix('12345A', '12345B') == 5
local function common_prefix(a: string, b: string): integer
  local len = math.min(#a, #b)
  if len == 0 then
    return 0
  end
  for i = 1, len do
    if a:sub(i,i) ~= b:sub(i,i) then
      return i - 1
    end
  end
  return len
end

-- Returns 0-based indices of start of common suffix
--
-- a, b - strings
-- start - 0-based index to start from
--
-- common_suffix('', '', 0) ==
local function common_suffix(a: string, b: string, start: integer): integer, integer
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

local type Region = {integer, string, integer, integer}

local function diff(rline: string, aline: string, rlinenr: integer, alinenr: integer, rprefix: integer, aprefix: integer, regions: {Region}, whole_line: boolean)
  -- print(string.format("diff '%s' '%s' %d %d %d %d", rline, aline, rlinenr, alinenr, rprefix, aprefix))
  -- diff marker does not count as a difference in prefix
  local start = whole_line and 2 or 1
  local prefix = common_prefix(rline:sub(start), aline:sub(start))
  if whole_line then
    prefix = prefix + 1
  end
  local rsuffix, asuffix = common_suffix(rline, aline, prefix+1)

  -- region of change (common prefix and suffix removed)
  local rtext = rline:sub(prefix+1, rsuffix)
  local atext = aline:sub(prefix+1, asuffix)

  -- print('prefix:'..prefix)
  -- print('rsuffix:'..rsuffix)
  -- print('asuffix:'..asuffix)
  -- print('rtext:"'..rtext..'"')
  -- print('atext:"'..atext..'"')

  -- singular insertion
  if rtext == '' then
    if not whole_line or #atext ~= #aline then -- not whole line
      regions[#regions+1] = {alinenr, '+', aprefix+prefix+1, aprefix+asuffix}
    end
  end

  -- singular deletion
  if atext == '' then
    if not whole_line or #rtext ~= #rline then -- not whole line
      regions[#regions+1] = {rlinenr, '-', rprefix+prefix+1, rprefix+rsuffix}
    end
  end

  if rtext == '' or atext == '' then
    return
  end

  -- two insertions
  local j = vim.fn.stridx(atext, rtext)
  if j ~= -1 then
    regions[#regions+1] = {alinenr, '+', aprefix+prefix+1         , aprefix+prefix+j}
    regions[#regions+1] = {alinenr, '+', aprefix+prefix+1+j+#rtext, aprefix+asuffix-1}
    return
  end

  -- two deletions
  local k = vim.fn.stridx(rtext, atext)
  if k ~= -1 then
    regions[#regions+1] = {rlinenr, '-', rprefix+prefix+1         , rprefix+prefix+k}
    regions[#regions+1] = {rlinenr, '-', rprefix+prefix+1+k+#atext, rprefix+rsuffix}
    return
  end

  -- two edits
  local lcs = get_lcs(rtext, atext)
  -- print('lcs:"'..lcs..'"')

  -- TODO do we need to ensure we don't get more than 2 elements when splitting?
  if #lcs > gap_between_regions then
    local redits = vim.split(rtext, lcs, true)
    local aedits = vim.split(atext, lcs, true)
    -- print('diff1')
    diff(redits[1], aedits[1], rlinenr, alinenr, rprefix+prefix                , aprefix+prefix                , regions, false)
    -- print('diff2')
    diff(redits[2], aedits[2], rlinenr, alinenr, rprefix+prefix+#redits[1]+#lcs, aprefix+prefix+#aedits[1]+#lcs, regions, false)
    return
  end

  -- fall back to highlighting entire changed area

  -- if a change (but not the whole line)
  if not whole_line or ((prefix ~= 0 or rsuffix ~= #rline) and prefix+1 < rsuffix) then
    regions[#regions+1] = {rlinenr, '-', rprefix+prefix+1, rprefix+rsuffix}
  end

  -- if a change (but not the whole line)
  if not whole_line or ((prefix ~= 0 or asuffix ~= #aline) and prefix+1 < asuffix) then
    regions[#regions+1] = {alinenr, '+', aprefix+prefix+1, aprefix+asuffix}
  end
end

-- Calculates the changed portions of lines.
--
-- Based on:
--
-- - diff-highlight (included with git)
--   https://github.com/git/git/blob/master/contrib/diff-highlight/DiffHighlight.pm
--
-- - Diff Strategies, Neil Fraser
--   https://neil.fraser.name/writing/diff/
--
--
-- Returns a list of intra-line changed regions.
-- Each element is a list:
--
--   [
--     line number (1-based),
--     type ('+' or '-'),
--     start column (1-based, inclusive),
--     stop column (1-based, inclusive),
--   ]
--
-- Args:
--   hunk_body - list of lines
function M.process(hunk_body: {string}): {Region}
  -- Check whether we have the same number of lines added as removed.
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

  local regions: {Region}
  regions = {}

  -- regions = setmetatable({}, {
  --   __newindex = function(r: {Region}, i: integer, value: Region)
  --     local lno = debug.getinfo(2, "Sl").currentline
  --     print(('(line %d) regions += %s'):format(lno, vim.inspect(value)))
  --     rawset(r, i, value)
  --   end
  -- })

  for i = 1, removed do
    -- pair lines by position
    local rline = hunk_body[i]
    local aline = hunk_body[i + removed]

    diff(rline, aline, i, i+removed, 0, 0, regions, true)
  end

  return regions
end

return M
