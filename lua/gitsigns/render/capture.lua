local api = vim.api

local Inspect = require('gitsigns.inspect')

local M = {}
local source_hls_supported = vim.fn.has('nvim-0.12') == 1

--- @class Gitsigns.CapturedSegment
--- @field start_col integer
--- @field end_col integer
--- @field hl Gitsigns.HlStack

--- @param value integer
--- @param lower integer
--- @param upper integer
--- @return integer
local function clamp(value, lower, upper)
  return math.min(math.max(value, lower), upper)
end

--- Compute an item's effective byte range on a single row.
--- @param item Gitsigns.InspectItem
--- @param row integer
--- @param start_col integer
--- @param end_col integer
--- @return integer? start_col
--- @return integer? end_col
local function layer_bounds_on_row(item, row, start_col, end_col)
  local item_row = item.row or row
  local item_end_row = item.end_row or item_row
  if row < item_row or row > item_end_row then
    return
  end

  local s = start_col
  if item_row == row then
    s = math.max(item.col or start_col, start_col)
  end

  local e
  if item_end_row > row then
    -- Multi-row highlights cover the rest of this row.
    e = end_col + 1
  else
    e = math.min(item.end_col or end_col, end_col)
  end

  if e <= s then
    return
  end

  return s, e
end

--- @param inspected Gitsigns.InspectRange
--- @return Gitsigns.RenderLayer[]
local function layers_from_inspected(inspected)
  local layers = {} --- @type Gitsigns.RenderLayer[]
  local row = inspected.row
  local start_col = inspected.start_col
  local end_col = inspected.end_col

  for _, item in ipairs(inspected.items) do
    local hl = item.hl_group
    if hl ~= nil and hl ~= '' then
      local s, e = layer_bounds_on_row(item, row, start_col, end_col)
      if s and e then
        layers[#layers + 1] = {
          start_col = s - start_col,
          end_col = e - start_col,
          priority = item.priority,
          hl_group = hl,
        }
      end
    end
  end

  return layers
end

--- @param bufnr integer
--- @param row integer
--- @param start_col? integer
--- @param end_col? integer
--- @return Gitsigns.CapturedLine
function M.capture_line(bufnr, row, start_col, end_col)
  local line = api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ''
  local line_len = #line

  --- @type integer
  local start_col0 = start_col or 0
  --- @type integer
  local end_col0 = end_col or line_len
  local s = clamp(start_col0, 0, line_len)
  local e = clamp(end_col0, s, line_len)
  if not source_hls_supported then
    return {
      text = line:sub(s + 1, e),
      layers = {},
    }
  end
  local inspected = Inspect.inspect_range(bufnr, row, s, e)

  return {
    text = line:sub(s + 1, e),
    layers = layers_from_inspected(inspected),
  }
end

--- @param bufnr integer
--- @param start_row integer
--- @param count integer
--- @param opts? {start_col?:integer, end_col?:integer}
--- @return Gitsigns.CapturedLine[]
function M.capture_lines(bufnr, start_row, count, opts)
  opts = opts or {}
  local lines = {} --- @type Gitsigns.CapturedLine[]
  for i = 1, math.max(count, 0) do
    local row = start_row + i - 1
    lines[i] = M.capture_line(bufnr, row, opts.start_col, opts.end_col)
  end
  return lines
end

--- @param bufnr integer
--- @param node Gitsigns.Hunk.Node
--- @param opts? {start_col?:integer, end_col?:integer}
--- @return Gitsigns.CapturedLine[]
function M.capture_node(bufnr, node, opts)
  return M.capture_lines(bufnr, node.start - 1, node.count, opts)
end

--- @param line Gitsigns.CapturedLine
--- @return integer[]
function M.boundaries(line)
  local line_len = #line.text
  local cols = {
    [0] = true,
    [line_len] = true,
  }

  for _, layer in ipairs(line.layers) do
    if layer.start_col > 0 and layer.start_col < line_len then
      cols[layer.start_col] = true
    end
    if layer.end_col > 0 and layer.end_col < line_len then
      cols[layer.end_col] = true
    end
  end

  local ret = {} --- @type integer[]
  for col in pairs(cols) do
    ret[#ret + 1] = col
  end
  table.sort(ret)
  return ret
end

--- @param line Gitsigns.CapturedLine
--- @param col integer
--- @return Gitsigns.HlStack
function M.hl_stack_at(line, col)
  local stack = {} --- @type Gitsigns.HlStack
  for _, layer in ipairs(line.layers) do
    if col >= layer.start_col and col < layer.end_col then
      Inspect.append_hl_group(stack, layer.hl_group)
    end
  end
  return stack
end

--- @param line Gitsigns.CapturedLine
--- @return Gitsigns.CapturedSegment[]
function M.segments(line)
  local segments = {} --- @type Gitsigns.CapturedSegment[]
  local cols = M.boundaries(line)
  local current_hl --- @type Gitsigns.HlStack?
  local current_start = 0

  for i = 1, #cols - 1 do
    local col = assert(cols[i])
    local hl = M.hl_stack_at(line, col)
    if current_hl == nil then
      current_hl = hl
      current_start = col
    elseif not Inspect.same_hl(current_hl, hl) then
      segments[#segments + 1] = {
        start_col = current_start,
        end_col = col,
        hl = current_hl,
      }
      current_hl = hl
      current_start = col
    end
  end

  if current_hl then
    segments[#segments + 1] = {
      start_col = current_start,
      end_col = #line.text,
      hl = current_hl,
    }
  end

  return segments
end

return M
