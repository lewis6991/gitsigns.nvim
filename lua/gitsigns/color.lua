local M = {}

--- @param value integer
--- @return [integer, integer, integer]
function M.int_to_rgb(value)
  local r = bit.band(bit.rshift(value, 16), 0xFF)
  local g = bit.band(bit.rshift(value, 8), 0xFF)
  local b = bit.band(value, 0xFF)
  return { r, g, b }
end

--- @param rgb [integer, integer, integer]
--- @return integer
function M.rgb_to_int(rgb)
  return rgb[1] * 0x10000 + rgb[2] * 0x100 + rgb[3]
end

--- @param stops [integer,integer,integer][]
--- @param t number 0-1
--- @return [integer, integer, integer]
function M.gradient(stops, t)
  assert(t >= 0 and t <= 1, 't must be between 0 and 1')
  local num_stops = #stops
  if num_stops < 2 then
    error('At least two color stops are required')
  end

  local segment_length = 1 / (num_stops - 1)
  local segment_index = math.floor(t / segment_length)

  if segment_index >= num_stops - 1 then
    local lstop = stops[num_stops]
    --- @cast lstop -?
    return { lstop[1], lstop[2], lstop[3] }
  end

  local local_t = (t - segment_index * segment_length) / segment_length

  local color1 = assert(stops[segment_index + 1])
  local color2 = assert(stops[segment_index + 2])

  return M.blend(color1, color2, local_t)
end

--- @param a integer
--- @param b integer
--- @param alpha number
--- @return integer
local function lerp(a, b, alpha)
  return math.floor(a + (b - a) * alpha)
end

--- @param color1 [integer, integer, integer]
--- @param color2 [integer, integer, integer]
--- @param alpha number 0-1
--- @return [integer, integer, integer]
function M.blend(color1, color2, alpha)
  return {
    lerp(color1[1], color2[1], alpha),
    lerp(color1[2], color2[2], alpha),
    lerp(color1[3], color2[3], alpha),
  }
end

local temp_color_stops = {
  { 0, 0, 255 }, -- Blue
  { 255, 0, 0 }, -- Red
  { 255, 255, 0 }, -- Yellow
}

--- @param value number 0-1
--- @return [integer, integer, integer]
function M.temp(value)
  return M.gradient(temp_color_stops, value)
end

return M
