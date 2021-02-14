
local M = {}

function M.parse_diff_line(line: string): Hunk
  local diffkey = vim.trim(vim.split(line, '@@', true)[2])

  -- diffKey: "-xx,n +yy"
  -- pre: {xx, n}, now: {yy}
  local pre, now = unpack(vim.tbl_map(function(s: string): {string}
    return vim.split(string.sub(s, 2), ',')
  end, vim.split(diffkey, ' ')) as {{string}})

  local removed = { start = tonumber(pre[1]), count = tonumber(pre[2]) or 1 }
  local added   = { start = tonumber(now[1]), count = tonumber(now[2]) or 1 }

  local hunk: Hunk = {
    start   = added.start,
    head    = line,
    lines   = {},
    removed = removed,
    added   = added
  }

  if added.count == 0 then
    -- delete
    hunk.dend = added.start
    hunk.type = "delete"
  elseif removed.count == 0 then
    -- add
    hunk.dend = added.start + added.count - 1
    hunk.type = "add"
  else
    -- change
    hunk.dend = added.start + math.min(added.count, removed.count) - 1
    hunk.type = "change"
  end
  return hunk
end

function M.get_range(hunk: Hunk): number, number
  local dend = hunk.dend
  if hunk.type == "change" then
    local add, remove = hunk.added.count, hunk.removed.count
    if add > remove then
      dend = dend + add - remove
    end
  end
  return hunk.start, dend
end

function M.process_hunks(hunks: {Hunk}): {Sign}
  local signs = {}
  for _, hunk in ipairs(hunks) do
    for i = hunk.start, hunk.dend do
      local topdelete = hunk.type == 'delete' and i == 0
      local changedelete = hunk.type == 'change' and hunk.removed.count > hunk.added.count and i == hunk.dend
      local count = hunk.type == 'add' and hunk.added.count or hunk.removed.count
      table.insert(signs, {
        type = topdelete and 'topdelete' or changedelete and 'changedelete' or hunk.type,
        lnum = topdelete and 1 or i,
        count = i == hunk.start and count
      })
    end
    if hunk.type == "change" then
      local add, remove = hunk.added.count, hunk.removed.count
      if add > remove then
        for i = 1, add - remove do
          local count = add - remove
          table.insert(signs, {
            type = 'add',
            lnum = hunk.dend + i,
            count = i == 1 and count
          })
        end
      end
    end
  end

  return signs
end

function M.create_patch(relpath: string, hunk: Hunk, mode_bits: string, invert: boolean): {string}
  invert = invert or false
  local type_, added, removed = hunk.type, hunk.added, hunk.removed

  local ps, pc, ns, nc = unpack(({
    add    = {removed.start + 1, 0            , removed.start + 1, added.count},
    delete = {removed.start    , removed.count, removed.start    , 0          },
    change = {removed.start    , removed.count, removed.start    , added.count}
  })[type_])

  local lines = hunk.lines

  if invert then
    ps, pc, ns, nc = ns, nc, ps, pc

    lines = vim.tbl_map(function(l: string): string
      if vim.startswith(l, '+') then
        l = '-'..string.sub(l, 2, -1)
      elseif vim.startswith(l, '-') then
        l = '+'..string.sub(l, 2, -1)
      end
      return l
    end, lines) as {string}
  end

  return {
    string.format('diff --git a/%s b/%s', relpath, relpath),
    'index 000000..000000 '..mode_bits,
    '--- a/'..relpath,
    '+++ b/'..relpath,
    string.format('@@ -%s,%s +%s,%s @@', ps, pc, ns, nc),
    unpack(lines as {string})
  }
end

function M.get_summary(hunks: {Hunk}): StatusObj
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
      status.added   = status.added   + add - min
      status.removed = status.removed + remove - min
    end
  end

  return status
end

function M.find_hunk(lnum: number, hunks: {Hunk}): Hunk

  for _, hunk in ipairs(hunks) do
    if lnum == 1 and hunk.start == 0 and hunk.dend == 0 then
      return hunk
    end

    local dend =
      hunk.type == 'change' and hunk.added.count > hunk.removed.count and
        (hunk.dend + hunk.added.count - hunk.removed.count) or
        hunk.dend

    if hunk.start <= lnum and dend >= lnum then
      return hunk
    end
  end
end

return M
