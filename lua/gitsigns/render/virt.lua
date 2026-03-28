local Capture = require('gitsigns.render.capture')
local Inspect = require('gitsigns.inspect')

local M = {}

--- @class Gitsigns.RenderLayer
--- @field start_col integer
--- @field end_col integer
--- @field priority integer
--- @field hl_group Gitsigns.HlName|Gitsigns.HlStack

--- @class Gitsigns.CapturedLine
--- @field text string
--- @field layers Gitsigns.RenderLayer[]

--- @class Gitsigns.RenderVirtOpts
--- @field pad_width? integer
--- @field pad_hl? Gitsigns.HlName|Gitsigns.HlStack
--- @field default_hl? Gitsigns.HlName|Gitsigns.HlStack
--- @field pad_with_eol_hl? boolean
--- @field prefix? Gitsigns.VirtTextChunk[][]|fun(line_index: integer, line: Gitsigns.CapturedLine): Gitsigns.VirtTextChunk[]?

--- @param chunks Gitsigns.VirtTextChunk[]
--- @param text string
--- @param hl Gitsigns.HlName|Gitsigns.HlStack
local function add_chunk(chunks, text, hl)
  if text == '' then
    return
  end

  hl = Inspect.normalize_hl(hl)

  local prev = chunks[#chunks]
  if prev and Inspect.same_hl(prev[2], hl) then
    prev[1] = prev[1] .. text
    return
  end

  chunks[#chunks + 1] = { text, hl }
end

M.add_chunk = add_chunk

--- @param chunks Gitsigns.VirtTextChunk[]?
--- @return Gitsigns.VirtTextChunk[]
local function copy_chunks(chunks)
  local ret = {} --- @type Gitsigns.VirtTextChunk[]
  for _, chunk in ipairs(chunks or {}) do
    ret[#ret + 1] = { chunk[1], chunk[2] }
  end
  return ret
end

--- @param opts Gitsigns.RenderVirtOpts
--- @param line_index integer
--- @param line Gitsigns.CapturedLine
--- @return Gitsigns.VirtTextChunk[]
local function line_prefix(opts, line_index, line)
  local prefix = opts.prefix
  if not prefix then
    return {}
  end

  if type(prefix) == 'function' then
    return copy_chunks(prefix(line_index, line))
  end

  --- @cast prefix Gitsigns.VirtTextChunk[][]
  return copy_chunks(prefix[line_index])
end

--- @param line Gitsigns.CapturedLine
--- @param opts Gitsigns.RenderVirtOpts
--- @return Gitsigns.VirtTextChunk[]
local function render_line(line, opts)
  local text = line.text
  local text_len = #text
  local chunks = {} --- @type Gitsigns.VirtTextChunk[]

  local cols = Capture.boundaries(line)
  for i = 1, #cols - 1 do
    local start_col = assert(cols[i])
    local end_col = assert(cols[i + 1])
    if end_col > start_col then
      local segment_hl = Capture.hl_stack_at(line, start_col)
      local hl = #segment_hl > 0 and Inspect.normalize_hl(segment_hl)
        or (opts.default_hl or 'Normal')
      add_chunk(chunks, text:sub(start_col + 1, end_col), hl)
    end
  end

  local pad_width = opts.pad_width
  if pad_width then
    local display_width = vim.fn.strdisplaywidth(text)
    local padding_width = math.max(pad_width - display_width, 0)
    if padding_width > 0 then
      local hl = opts.pad_hl
      if not hl and opts.pad_with_eol_hl ~= false then
        local sample_col = text_len > 0 and text_len - 1 or 0
        local eol_hl = Capture.hl_stack_at(line, sample_col)
        if #eol_hl > 0 then
          hl = Inspect.normalize_hl(eol_hl)
        end
      end
      add_chunk(chunks, string.rep(' ', padding_width), hl or opts.default_hl or 'Normal')
    end
  end

  return chunks
end

--- Render captured lines to extmark `virt_lines`.
--- @param lines Gitsigns.CapturedLine[]
--- @param opts? Gitsigns.RenderVirtOpts
--- @return Gitsigns.VirtTextChunk[][]
function M.render(lines, opts)
  opts = opts or {}
  local virt_lines = {} --- @type Gitsigns.VirtTextChunk[][]

  for i, line in ipairs(lines) do
    local vline = line_prefix(opts, i, line)
    vim.list_extend(vline, render_line(line, opts))
    virt_lines[i] = vline
  end

  return virt_lines
end

return M
