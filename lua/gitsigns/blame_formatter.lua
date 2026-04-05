local util = require('gitsigns.util')

local M = {}

--- @class (exact) Gitsigns.BlameLineHighlight
--- @field start_col integer
--- @field end_col integer
--- @field hl_group Gitsigns.HlName|Gitsigns.HlStack

--- @param info Gitsigns.BlameInfoPublic
--- @param username string
--- @param opts? { self_author_text?: string }
--- @return Gitsigns.BlameInfoPublic
local function normalize_info(info, username, opts)
  local self_author_text = opts and opts.self_author_text
  if not (self_author_text and info.author == username) then
    return info
  end

  info = vim.deepcopy(info)
  info.author = self_author_text
  return info
end

--- @param chunks Gitsigns.BlameFmtChunk[]
--- @return Gitsigns.BlameFmtChunk[]
function M.sanitize_chunks(chunks)
  if type(chunks) ~= 'table' then
    error('blame formatter must return a list of [text, highlight] chunks')
  end

  local ret = {} --- @type Gitsigns.BlameFmtChunk[]
  for i, part in ipairs(chunks) do
    if type(part) ~= 'table' or type(part[1]) ~= 'string' then
      error(('invalid blame formatter chunk at index %d'):format(i))
    end

    local text = part[1]
    if text:find('\n', 1, true) then
      error('blame formatter chunks cannot contain newlines')
    end

    if text ~= '' then
      ret[#ret + 1] = { text, part[2] }
    end
  end

  return ret
end

--- @param fmt string
--- @param username string
--- @param info Gitsigns.BlameInfoPublic
--- @param opts? { self_author_text?: string }
--- @return string
function M.expand_string(fmt, username, info, opts)
  return util.expand_format(fmt, normalize_info(info, username, opts))
end

--- @param fmt string
--- @param username string
--- @param info Gitsigns.BlameInfoPublic
--- @param opts? { self_author_text?: string, token_hls?: table<string, Gitsigns.HlName|Gitsigns.HlStack> }
--- @return Gitsigns.BlameFmtChunk[]
--- @return boolean
function M.expand_chunks(fmt, username, info, opts)
  local ret = {} --- @type Gitsigns.BlameFmtChunk[]
  local saw_summary = false
  local token_hls = opts and opts.token_hls or nil
  info = normalize_info(info, username, opts)

  for _ = 1, 20 do -- loop protection
    local scol, ecol, match, key = fmt:find('(<([^:>]+):?([^>]*)>)')
    if not match then
      break
    end

    --- @cast scol integer
    --- @cast ecol integer
    --- @cast key string

    ret[#ret + 1], fmt = { fmt:sub(1, scol - 1) }, fmt:sub(ecol + 1)
    ret[#ret + 1] = { util.expand_format(match, info), token_hls and token_hls[key] }
    saw_summary = saw_summary or key == 'summary'
  end

  ret[#ret + 1] = { fmt }
  return M.sanitize_chunks(ret), saw_summary
end

--- @param chunks Gitsigns.BlameFmtChunk[]
--- @return string
--- @return Gitsigns.BlameLineHighlight[]
--- @return integer
function M.render_line(chunks)
  local highlights = {} --- @type Gitsigns.BlameLineHighlight[]
  local text = {} --- @type string[]
  local col = 0

  for _, part in ipairs(chunks) do
    local part_text, hl_group = part[1], part[2]
    text[#text + 1] = part_text

    local end_col = col + #part_text
    if hl_group and end_col > col then
      highlights[#highlights + 1] = {
        start_col = col,
        end_col = end_col,
        hl_group = hl_group,
      }
    end
    col = end_col
  end

  local line = table.concat(text)
  return line, highlights, vim.fn.strdisplaywidth(line)
end

return M
