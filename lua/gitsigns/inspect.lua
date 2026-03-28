local InspectPos = require('gitsigns.inspect.compat')

local M = {}

--- @alias Gitsigns.HlName string|integer
--- @alias Gitsigns.HlStack Gitsigns.HlName[]

--- @class Gitsigns.InspectPosItem
--- @field hl_group? Gitsigns.HlName|Gitsigns.HlStack highlight group name
--- @field hl_group_link string resolved highlight group (after following links)
--- @field row? integer start row (0-based)
--- @field col? integer start column (0-based)
--- @field end_row? integer end row (0-based, exclusive)
--- @field end_col? integer end column (0-based, exclusive)

--- @class Gitsigns.InspectPosTSItem : Gitsigns.InspectPosItem
--- @field capture string treesitter capture name
--- @field lang string parser language
--- @field metadata vim.treesitter.query.TSMetadata capture metadata
--- @field id integer capture id
--- @field pattern_id integer pattern id

--- @class Gitsigns.InspectPosExtmarkItem : Gitsigns.InspectPosItem
--- @field id integer extmark id
--- @field ns_id integer namespace id
--- @field ns string namespace name
--- Note: `opts.hl_group_link` is deprecated; use the top-level `hl_group_link` field.
--- @field opts vim.api.keyset.extmark_details raw extmark details from |nvim_buf_get_extmarks()|.

--- @class Gitsigns.InspectPosResult
--- @inlinedoc
--- @field buffer integer buffer number
--- @field row integer queried start row (0-based)
--- @field col integer queried start column (0-based)
--- @field end_row? integer queried end row (only set for range queries)
--- @field end_col? integer queried end column (only set for range queries)
--- @field treesitter Gitsigns.InspectPosTSItem[]
--- @field syntax Gitsigns.InspectPosItem[]
--- @field extmarks Gitsigns.InspectPosExtmarkItem[]
--- @field semantic_tokens Gitsigns.InspectPosExtmarkItem[]

--- @class Gitsigns.InspectItem : Gitsigns.InspectPosItem
--- @field priority integer
--- @field order integer
--- @field hl_group? Gitsigns.HlName|Gitsigns.HlStack
--- @field hl_group_link? string
--- @field capture? string
--- @field lang? string
--- @field metadata? vim.treesitter.query.TSMetadata
--- @field pattern_id? integer
--- @field id? integer
--- @field ns? string
--- @field ns_id? integer
--- @field opts? {hl_group?:Gitsigns.HlName|Gitsigns.HlStack, hl_group_link?:string, priority?:integer, ns_id?:integer, end_row?:integer, end_col?:integer}

--- @class Gitsigns.InspectRange
--- @field buffer integer
--- @field row integer
--- @field start_col integer
--- @field end_col integer
--- @field items Gitsigns.InspectItem[]

--- @class Gitsigns.HlSegment
--- @field start_col integer
--- @field end_col integer
--- @field hl Gitsigns.HlStack

--- @param groups Gitsigns.HlStack
--- @return Gitsigns.HlName|Gitsigns.HlStack
function M.normalize_hl_groups(groups)
  if #groups == 1 and groups[1] ~= nil then
    return groups[1]
  end
  return groups
end

--- @param hl Gitsigns.HlName|Gitsigns.HlStack
--- @return Gitsigns.HlName|Gitsigns.HlStack
function M.normalize_hl(hl)
  if type(hl) == 'table' then
    return M.normalize_hl_groups(hl)
  end
  return hl
end

--- @param a Gitsigns.HlName|Gitsigns.HlStack
--- @param b Gitsigns.HlName|Gitsigns.HlStack
--- @return boolean
function M.same_hl(a, b)
  local ta, tb = type(a), type(b)
  if ta ~= tb then
    return false
  end
  if ta ~= 'table' then
    return a == b
  end

  --- @cast a Gitsigns.HlStack
  --- @cast b Gitsigns.HlStack
  if #a ~= #b then
    return false
  end
  for i = 1, #a do
    if a[i] ~= b[i] then
      return false
    end
  end
  return true
end

--- @param dest Gitsigns.HlStack
--- @param group Gitsigns.HlName|Gitsigns.HlStack|nil
function M.append_hl_group(dest, group)
  if not group or group == '' then
    return
  end
  if type(group) == 'table' then
    --- @cast group Gitsigns.HlStack
    for _, hl in ipairs(group) do
      if hl ~= '' then
        dest[#dest + 1] = hl
      end
    end
    return
  end
  dest[#dest + 1] = group
end

--- @param item {row?:integer, col?:integer, end_row?:integer, end_col?:integer}
--- @param row integer
--- @param col integer
--- @return boolean
local function item_overlaps_pos(item, row, col)
  local start_row = item.row or row
  local start_col = item.col or col
  local end_row = item.end_row or start_row
  local end_col = item.end_col or start_col

  if row < start_row or row > end_row then
    return false
  elseif row == start_row and col < start_col then
    return false
  elseif row == end_row and col >= end_col then
    return false
  end
  return true
end

--- Resolve the effective Treesitter priority for a capture item.
--- @param capture Gitsigns.InspectPosTSItem
--- @return integer
local function treesitter_priority(capture)
  local metadata = capture.metadata
  local capture_metadata = metadata[capture.id]
  local priority = metadata.priority
  if type(priority) == 'number' then
    --- @cast priority integer
    return priority
  end

  priority = type(capture_metadata) == 'table' and capture_metadata.priority or nil
  if type(priority) == 'number' then
    --- @cast priority integer
    return priority
  end

  local default_priority = vim.hl.priorities.treesitter
  --- @cast default_priority integer
  return default_priority
end

--- Collect byte-column boundaries where the active highlight stack can change.
--- @param inspected Gitsigns.InspectRange
--- @return integer[]
function M.boundaries(inspected)
  local cols = {
    [inspected.start_col] = true,
    [inspected.end_col] = true,
  }

  for _, item in ipairs(inspected.items) do
    local start_col = item.col or inspected.start_col
    local end_col = item.end_col or start_col

    if start_col > inspected.start_col and start_col < inspected.end_col then
      cols[start_col] = true
    end
    if end_col > inspected.start_col and end_col < inspected.end_col then
      cols[end_col] = true
    end
  end

  local ret = {} --- @type integer[]
  for col in pairs(cols) do
    ret[#ret + 1] = col
  end
  table.sort(ret)
  return ret
end

--- Return the highlight stack active at a byte column.
--- @param inspected Gitsigns.InspectRange
--- @param col integer
--- @return Gitsigns.HlStack
function M.hl_stack_at(inspected, col)
  local stack = {} --- @type Gitsigns.HlStack

  for _, item in ipairs(inspected.items) do
    if item.hl_group and item_overlaps_pos(item, inspected.row, col) then
      M.append_hl_group(stack, item.hl_group)
    end
  end

  return stack
end

--- Inspect a single-line range and normalize its highlights into ordered items.
--- @param bufnr integer
--- @param row integer
--- @param start_col integer
--- @param end_col integer
--- @return Gitsigns.InspectRange
function M.inspect_range(bufnr, row, start_col, end_col)
  assert(end_col >= start_col, 'end_col must be greater than or equal to start_col')

  local result = InspectPos.inspect_pos(bufnr, row, start_col, {
    end_row = row,
    -- UTF-8 codepoints are at most 4 bytes, so this always reaches at least
    -- the next byte boundary after end_col.
    end_col = end_col + 4,
  })

  --- @type Gitsigns.InspectRange
  local ret = {
    buffer = result.buffer,
    row = result.row,
    start_col = start_col,
    end_col = end_col,
    items = {},
  }

  --- Append a normalized item while preserving insertion order for equal priorities.
  --- @param items Gitsigns.InspectItem[]
  --- @param item Gitsigns.InspectPosItem
  --- @param priority integer
  local function add_item(items, item, priority)
    --- @cast item Gitsigns.InspectItem
    item.priority = priority
    item.order = #items + 1
    items[#items + 1] = item
  end

  for _, item in ipairs(result.syntax) do
    add_item(ret.items, item, 0)
  end
  for _, item in ipairs(result.treesitter) do
    add_item(ret.items, item, treesitter_priority(item))
  end
  for _, item in ipairs(result.semantic_tokens) do
    add_item(ret.items, item, item.opts.priority or 0)
  end
  for _, item in ipairs(result.extmarks) do
    add_item(ret.items, item, item.opts.priority or 0)
  end

  table.sort(ret.items, function(a, b)
    if a.priority == b.priority then
      return a.order < b.order
    end
    return a.priority < b.priority
  end)

  return ret
end

--- Split a single-line range into contiguous segments with identical highlight stacks.
--- @param bufnr integer
--- @param row integer
--- @param start_col integer
--- @param end_col integer
--- @return Gitsigns.InspectRange
--- @return Gitsigns.HlSegment[]
function M.hl_segments(bufnr, row, start_col, end_col)
  local inspected = M.inspect_range(bufnr, row, start_col, end_col)
  local segments = {} --- @type Gitsigns.HlSegment[]
  local current_hl --- @type Gitsigns.HlStack?
  local current_start = inspected.start_col
  local cols = M.boundaries(inspected)

  for i = 1, #cols - 1 do
    local col = assert(cols[i])
    local hl = M.hl_stack_at(inspected, col)
    if current_hl == nil then
      current_start = col
      current_hl = hl
    elseif not M.same_hl(current_hl, hl) then
      segments[#segments + 1] = {
        start_col = current_start,
        end_col = col,
        hl = current_hl,
      }
      current_start = col
      current_hl = hl
    end
  end

  if current_hl then
    segments[#segments + 1] = {
      start_col = current_start,
      end_col = end_col,
      hl = current_hl,
    }
  end

  return inspected, segments
end

return M
