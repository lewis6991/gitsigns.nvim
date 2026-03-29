local Inspect = require('gitsigns.inspect')

local M = {}

--- @param layers Gitsigns.RenderLayer[]
--- @param layer Gitsigns.RenderLayer
local function insert_layer(layers, layer)
  if layer.end_col <= layer.start_col then
    return
  end

  local index = #layers + 1
  for i = 1, #layers do
    if layer.priority < layers[i].priority then
      index = i
      break
    end
  end

  local prev = layers[index - 1]
  if
    prev
    and prev.end_col == layer.start_col
    and prev.priority == layer.priority
    and Inspect.same_hl(prev.hl_group, layer.hl_group)
  then
    prev.end_col = layer.end_col
    return
  end

  table.insert(layers, index, layer)
end

--- @param line Gitsigns.CapturedLine
--- @param start_col integer
--- @param end_col integer
--- @param hl_group Gitsigns.HlName|Gitsigns.HlStack
--- @param priority integer
--- @return Gitsigns.CapturedLine
function M.add_layer(line, start_col, end_col, hl_group, priority)
  line.layers = line.layers or {}
  local line_len = #line.text
  local s = math.max(start_col, 0)
  local e = math.max(end_col, s)
  if s > line_len then
    s = line_len
  end

  insert_layer(line.layers, {
    start_col = s,
    end_col = e,
    hl_group = Inspect.normalize_hl(hl_group),
    priority = priority,
  })

  return line
end

--- @param lines Gitsigns.CapturedLine[]
--- @param hl_group Gitsigns.HlName|Gitsigns.HlStack
--- @param priority integer
--- @param first_line? integer
--- @param last_line? integer
--- @return Gitsigns.CapturedLine[]
function M.add_full_line_layer(lines, hl_group, priority, first_line, last_line)
  first_line = first_line or 1
  last_line = last_line or #lines

  for i = first_line, last_line do
    local line = lines[i]
    if line then
      M.add_layer(line, 0, #line.text + 1, hl_group, priority)
    end
  end

  return lines
end

--- @param lines Gitsigns.CapturedLine[]
--- @param regions [integer, string, integer, integer][]
--- @param region_hl Gitsigns.HlName|fun(region_type:string, region:[integer,string,integer,integer]):Gitsigns.HlName?
--- @param priority integer
--- @param opts? {ensure_min_width?:boolean}
--- @return Gitsigns.CapturedLine[]
function M.add_word_diff_layers(lines, regions, region_hl, priority, opts)
  opts = opts or {}

  for _, region in ipairs(regions) do
    local line = lines[region[1]]
    if line then
      local hl = type(region_hl) == 'function' and region_hl(region[2], region) or region_hl
      if hl and hl ~= '' then
        local s = math.max(region[3] - 1, 0)
        local e = math.max(region[4] - 1, s)
        if opts.ensure_min_width and e == s then
          e = s + 1
        end
        M.add_layer(line, s, e, hl, priority)
      end
    end
  end

  return lines
end

return M
