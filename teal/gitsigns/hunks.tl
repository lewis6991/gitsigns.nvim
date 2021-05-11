local Sign = require('gitsigns.signs').Sign
local StatusObj = require('gitsigns.status').StatusObj

local record M
  record Hunk
    enum Type
      "add"
      "change"
      "delete"
    end

    type: Type
    head: string
    lines: {string}
    start: integer
    dend: integer
    vend: integer

    record Node
      start: integer
      count: integer
    end

    added: Node
    removed: Node
  end
end

local Hunk = M.Hunk

function M.create_hunk(start_a: integer, count_a: integer, start_b: integer, count_b: integer): Hunk
  local removed = { start = start_a, count = count_a }
  local added   = { start = start_b, count = count_b }

  local hunk: Hunk = {
    start   = added.start,
    lines   = {},
    removed = removed,
    added   = added
  }

  if added.count == 0 then
    -- delete
    hunk.dend = added.start
    hunk.vend = hunk.dend
    hunk.type = "delete"
  elseif removed.count == 0 then
    -- add
    hunk.dend = added.start + added.count - 1
    hunk.vend = hunk.dend
    hunk.type = "add"
  else
    -- change
    hunk.dend = added.start + math.min(added.count, removed.count) - 1
    hunk.vend = hunk.dend + math.max(added.count - removed.count, 0)
    hunk.type = "change"
  end

  return hunk
end

function M.parse_diff_line(line: string): Hunk
  local diffkey = vim.trim(vim.split(line, '@@', true)[2])

  -- diffKey: "-xx,n +yy"
  -- pre: {xx, n}, now: {yy}
  local pre, now = unpack(vim.tbl_map(function(s: string): {string}
    return vim.split(string.sub(s, 2), ',')
  end, vim.split(diffkey, ' ')) as {{string}})

  local hunk = M.create_hunk(
    tonumber(pre[1]) as integer, (tonumber(pre[2]) or 1) as integer,
    tonumber(now[1]) as integer, (tonumber(now[2]) or 1) as integer
  )
  hunk.head = line

  return hunk
end

function M.process_hunks(hunks: {Hunk}): {integer:Sign}
  local signs = {}
  for _, hunk in ipairs(hunks) do
    local count = hunk.type == 'add' and hunk.added.count or hunk.removed.count
    for i = hunk.start, hunk.dend do
      local topdelete = hunk.type == 'delete' and i == 0
      local changedelete = hunk.type == 'change' and hunk.removed.count > hunk.added.count and i == hunk.dend
      -- topdelete signs get placed one row lower
      signs[topdelete and 1 or i] = {
        type = topdelete and 'topdelete' or changedelete and 'changedelete' or hunk.type,
        count = i == hunk.start and count
      }
    end
    if hunk.type == "change" then
      local add, remove = hunk.added.count, hunk.removed.count
      if add > remove then
        local count_diff = add - remove
        for i = 1, count_diff do
          signs[hunk.dend + i] = {
            type = 'add',
            count = i == 1 and count_diff
          }
        end
      end
    end
  end

  return signs
end

function M.create_patch(relpath: string, hunks: {Hunk}, mode_bits: string, invert: boolean): {string}
  invert = invert or false

  local results = {
    string.format('diff --git a/%s b/%s', relpath, relpath),
    'index 000000..000000 '..mode_bits,
    '--- a/'..relpath,
    '+++ b/'..relpath,
  }

  for _, process_hunk in ipairs(hunks) do
    local start:integer
    local pre_count:integer
    local now_count:integer

    local lines = process_hunk.lines

    if not invert then
      start, pre_count, now_count =
        process_hunk.removed.start, process_hunk.removed.count, process_hunk.added.count

      if process_hunk.type == 'add' then
        start = start + 1
      end
    else
      start, pre_count, now_count =
        process_hunk.added.start, process_hunk.added.count, process_hunk.removed.count

      if process_hunk.type == 'delete' then
        start = start + 1
      end

      lines = vim.tbl_map(function(l: string): string
        if vim.startswith(l, '+') then
          l = '-'..string.sub(l, 2, -1)
        elseif vim.startswith(l, '-') then
          l = '+'..string.sub(l, 2, -1)
        end
        return l
      end, lines) as {string}
    end

    table.insert(results, string.format('@@ -%s,%s +%s,%s @@', start, pre_count, start, now_count))
    for _, line in ipairs(lines) do
      table.insert(results, line)
    end
  end

  return results
end

function M.get_summary(hunks: {Hunk}, head: string): StatusObj
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
      status.added   = status.added   + add - min
      status.removed = status.removed + remove - min
    end
  end

  return status
end

function M.find_hunk(lnum: number, hunks: {Hunk}): Hunk
  for _, hunk in ipairs(hunks) do
    if lnum == 1 and hunk.start == 0 and hunk.vend == 0 then
      return hunk
    end

    if hunk.start <= lnum and hunk.vend >= lnum then
      return hunk
    end
  end
end

function M.find_nearest_hunk(lnum: number, hunks: {Hunk}, forwards: boolean, wrap: boolean): Hunk
  local ret: Hunk
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

function M.merge(a: {Hunk}, b: {Hunk}): {Hunk}
  if not a and not b then return end
  a, b = a or {}, b or {}
  local max = math.max(#a, #b)

  local ai = 1
  local bi = 1

  local r: {Hunk} = {}

  -- For every iteration:
  --   - r[i] must be assigned non-nil
  --   - Atleast ai or bi must be incremented
  for i = 1, max do
    local ah, bh = a[ai], b[bi]
    if not ah or ah.start > bh.start then
      r[i] = bh
      bi = bi + 1
    elseif not bh or ah.start < bh.start then
      r[i] = ah
      ai = ai + 1
    else
      -- if they begin on the same line, place the shorter one first so
      -- navigating backwards works
      if ah.vend <= bh.vend then
        r[i] = ah
        r[i] = bh
      else
        r[i] = bh
        r[i] = ah
      end
      ai = ai + 1
      bi = bi + 1
    end
  end

  return r
end

function M.extract_lines(hunk: Hunk, removed: boolean): {string}
  return vim.tbl_map(function(l: string): string
    return string.sub(l, 2, -1)
  end, vim.tbl_filter(function(l: string): boolean
    return vim.startswith(l, removed and '-' or '+')
  end, hunk.lines)) as {string}
end

-- local function compare_new(a: Hunk, b: Hunk): boolean
--   if a.added.start ~= b.added.start then
--     return false
--   end

--   if a.added.count ~= b.added.count then
--     return false
--   end

--   local a_lines = M.extract_lines(a, false)
--   local b_lines = M.extract_lines(b, false)

--   for i = 1, #a_lines do
--     if a_lines[i] ~= b_lines[i] then
--       return false
--     end
--   end

--   return true
-- end

-- Return hunks in a using b's hunks as a filter. Only compare the 'new' section
-- of the hunk.
--
-- Eg. Given:
--
--     a = {
--         1 = '@@ -24 +25,1 @@',
--         2 = '@@ -32 +34,1 @@',
--         3 = '@@ -37 +40,1 @@'
--     }
--
--     b = {
--         1 = '@@ -26 +25,1 @@'
--     }
--
-- Since a[1] and b[1] introduce the same changes to the buffer (both have
-- +25,1), we exclude this hunk in the output so we return:
--
--     {
--         1 = '@@ -32 +34,1 @@',
--         2 = '@@ -37 +40,1 @@'
--     }
--
-- function M.filter_new(a: {Hunk}, b: {Hunk}): {Hunk}
--   if not a and not b then return end
--   a, b = a or {}, b or {}
--   local max = math.max(#a, #b)

--   local ai = 1
--   local bi = 1

--   local r: {Hunk} = {}

--   for _ = 1, max do
--     local ah, bh = a[ai], b[bi]
--     if not ah then
--       -- Reached the end of a
--       break
--     end
--     if not bh then
--       -- Reached the end of b, add remainder of a
--       for n = ai, #a do
--         r[#r+1] = a[n]
--       end
--       break
--     end
--     if ah.start > bh.start then
--       -- a pointer is ahead of b; increment b pointer
--       bi = bi + 1
--     elseif ah.start < bh.start then
--       -- b pointer is ahead of a; add ah to ret and increment a pointer
--       r[#r+1] = ah
--       ai = ai + 1
--     else
--       -- ah and bh start on the same line, if hunks have the same changes then
--       -- skip (filtered) otherwise add ah to ret and increment both hunk
--       -- pointers
--       if not compare_new(ah, bh) then
--         r[#r+1] = ah
--       end
--       ai = ai + 1
--       bi = bi + 1
--     end
--   end

--   return r
-- end


return M
