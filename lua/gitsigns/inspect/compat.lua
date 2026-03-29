local api = vim.api

-- Vendored from vim._inspector with minimal changes to support single-row
-- ranges.

local M = {}

local defaults = {
  syntax = true,
  treesitter = true,
  extmarks = true,
  semantic_tokens = true,
}

--- @class Gitsigns.InspectCompatFilter
--- @field syntax? boolean
--- @field treesitter? boolean
--- @field extmarks? boolean|'all'
--- @field semantic_tokens? boolean
--- @field end_row? integer
--- @field end_col? integer

--- @class Gitsigns.InspectCompatCapture
--- @field capture string
--- @field lang string
--- @field metadata vim.treesitter.query.TSMetadata
--- @field id integer
--- @field pattern_id integer

--- @param line string
--- @param col integer
--- @return integer
local function next_boundary(line, col)
  local nchars = vim.str_utfindex(line, 'utf-32')
  for i = 0, nchars do
    local byte_col = vim.str_byteindex(line, 'utf-32', i)
    if byte_col > col then
      return byte_col
    end
  end
  return col + 1
end

--- @param line string
--- @param start_col integer
--- @param end_col integer
--- @return integer[]
local function range_columns(line, start_col, end_col)
  local cols = {
    [start_col] = true,
    [end_col] = true,
  }

  local nchars = vim.str_utfindex(line, 'utf-32')
  for i = 0, nchars do
    local col = vim.str_byteindex(line, 'utf-32', i)
    if col >= start_col and col <= end_col then
      cols[col] = true
    end
  end

  local ret = {} --- @type integer[]
  for col in pairs(cols) do
    ret[#ret + 1] = col
  end
  table.sort(ret)
  return ret
end

--- @param hl Gitsigns.HlName|Gitsigns.HlStack
--- @return Gitsigns.HlName|Gitsigns.HlStack|nil
--- @return string?
local function resolve_hl_group(hl)
  if hl == nil or hl == '' then
    return nil, nil
  end

  if type(hl) == 'table' then
    local groups = {} --- @type Gitsigns.HlStack
    for _, group in ipairs(hl) do
      local resolved = select(1, resolve_hl_group(group))
      if resolved and resolved ~= '' then
        if type(resolved) == 'table' then
          vim.list_extend(groups, resolved)
        else
          groups[#groups + 1] = resolved
        end
      end
    end
    return #groups > 0 and groups or nil, nil
  end

  local hlid --- @type integer?
  if type(hl) == 'number' then
    hlid = hl --[[@as integer]]
  elseif type(hl) == 'string' then
    hlid = api.nvim_get_hl_id_by_name(hl)
  end

  if not hlid then
    return nil, nil
  end

  local name = vim.fn.synIDattr(hlid, 'name')
  if name == '' then
    return nil, nil
  end

  local link = vim.fn.synIDattr(vim.fn.synIDtrans(hlid), 'name')
  return name, link
end

--- @param data table
--- @return table
local function resolve_hl(data)
  local resolved, link = resolve_hl_group(data.hl_group)
  data.hl_group = resolved
  data.hl_group_link = link or ''
  return data
end

--- @return table<integer, string>
local function namespace_map()
  local nsmap = {} --- @type table<integer, string>
  for name, id in pairs(api.nvim_get_namespaces()) do
    nsmap[id] = name
  end
  return nsmap
end

--- @param extmark vim.api.keyset.get_extmark_item
--- @param nsmap table<integer, string>
--- @return Gitsigns.InspectPosExtmarkItem
local function extmark_to_map(extmark, nsmap)
  local details = (extmark[4] or {}) --[[@as vim.api.keyset.extmark_details]]
  local end_row = details.end_row
  local end_col = details.end_col
  if details.hl_eol and end_row == nil and end_col == nil then
    end_row = extmark[2] + 1
    end_col = 0
  end

  local item = {
    id = extmark[1],
    row = extmark[2],
    col = extmark[3],
    end_row = end_row or extmark[2],
    end_col = end_col or extmark[3],
    hl_group = details.hl_group,
    hl_group_link = '',
    opts = details,
    ns_id = details.ns_id,
    ns = details.ns_id and nsmap[details.ns_id] or '',
  } --- @type Gitsigns.InspectPosExtmarkItem

  return resolve_hl(item) --[[@as Gitsigns.InspectPosExtmarkItem]]
end

--- @param extmark table
--- @param row integer
--- @param col integer
--- @return boolean
local function overlaps_single_pos(extmark, row, col)
  if row < extmark.row or row > extmark.end_row then
    return false
  end
  if row == extmark.row and col < extmark.col then
    return false
  end
  return row < extmark.end_row or col < extmark.end_col
end

--- @param capture table
--- @return string
local function capture_key(capture)
  local metadata = capture.metadata or {}
  local capture_metadata = metadata[capture.id]
  local priority = metadata.priority
    or (type(capture_metadata) == 'table' and capture_metadata.priority or nil)
    or ''
  return table.concat({
    capture.capture,
    capture.lang,
    tostring(capture.id),
    tostring(capture.pattern_id or ''),
    tostring(priority),
  }, '\0')
end

--- @param bufnr integer
--- @param row integer
--- @param cols integer[]
--- @return Gitsigns.InspectPosTSItem[]
local function collect_treesitter(bufnr, row, cols)
  local items = {} --- @type Gitsigns.InspectPosTSItem[]
  local previous = {} --- @type table<string, Gitsigns.InspectPosTSItem>

  for i = 1, #cols - 1 do
    local col = assert(cols[i])
    local next_col = assert(cols[i + 1])
    local active = {} --- @type table<string, Gitsigns.InspectPosTSItem>

    for _, capture in pairs(vim.treesitter.get_captures_at_pos(bufnr, row, col)) do
      --- @cast capture Gitsigns.InspectCompatCapture
      local key = capture_key(capture)
      local item = previous[key]

      if item and item.end_col == col then
        item.end_col = next_col
        active[key] = item
      else
        local new_item = resolve_hl({
          capture = capture.capture,
          lang = capture.lang,
          metadata = capture.metadata,
          id = capture.id,
          pattern_id = capture.pattern_id,
          hl_group = '@' .. capture.capture .. '.' .. capture.lang,
          row = row,
          col = col,
          end_row = row,
          end_col = next_col,
        }) --[[@as Gitsigns.InspectPosTSItem]]
        items[#items + 1] = new_item
        active[key] = new_item
      end
    end

    previous = active
  end

  return items
end

--- @param a integer[]
--- @param b integer[]
--- @return boolean
local function same_stack(a, b)
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

--- @param bufnr integer
--- @param row integer
--- @param cols integer[]
--- @return Gitsigns.InspectPosItem[]
local function collect_syntax(bufnr, row, cols)
  return api.nvim_buf_call(bufnr, function()
    local items = {} --- @type Gitsigns.InspectPosItem[]
    local previous = {} --- @type integer[]
    local open = {} --- @type Gitsigns.InspectPosItem[]

    for i = 1, #cols - 1 do
      local col = assert(cols[i])
      local next_col = assert(cols[i + 1])
      local stack = vim.fn.synstack(row + 1, col + 1)

      if same_stack(stack, previous) then
        for _, item in ipairs(open) do
          item.end_col = next_col
        end
      else
        open = {}
        for _, syn_id in ipairs(stack) do
          local item = resolve_hl({
            hl_group = vim.fn.synIDattr(syn_id, 'name'),
            row = row,
            col = col,
            end_row = row,
            end_col = next_col,
          }) --[[@as Gitsigns.InspectPosItem]]
          items[#items + 1] = item
          open[#open + 1] = item
        end
        previous = stack
      end
    end

    return items
  end)
end

--- @param bufnr integer
--- @param row integer
--- @param col integer
--- @param opts? Gitsigns.InspectCompatFilter
--- @return Gitsigns.InspectPosResult
function M.inspect_pos(bufnr, row, col, opts)
  opts = vim.tbl_deep_extend('force', defaults, opts or {}) --[[@as Gitsigns.InspectCompatFilter]]

  local has_range = opts.end_row ~= nil and opts.end_col ~= nil
  if has_range and opts.end_row ~= row then
    error('gitsigns inspect backend only supports single-row ranges')
  end

  local line = api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ''
  local stop_col = has_range and assert(opts.end_col) or next_boundary(line, col)

  if stop_col < col then
    error('end_col must be greater than or equal to col')
  end

  local cols = range_columns(line, col, stop_col)

  --- @type Gitsigns.InspectPosResult
  local result = {
    treesitter = {}, --- @type Gitsigns.InspectPosTSItem[]
    syntax = {}, --- @type Gitsigns.InspectPosItem[]
    extmarks = {}, --- @type Gitsigns.InspectPosExtmarkItem[]
    semantic_tokens = {}, --- @type Gitsigns.InspectPosExtmarkItem[]
    buffer = bufnr,
    row = row,
    col = col,
  }

  if has_range then
    result.end_row = row
    result.end_col = stop_col
  end

  if opts.treesitter then
    result.treesitter = collect_treesitter(bufnr, row, cols)
  end

  if opts.syntax and api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].syntax ~= '' then
    result.syntax = collect_syntax(bufnr, row, cols)
  end

  if opts.extmarks or opts.semantic_tokens then
    local raw_extmarks = api.nvim_buf_get_extmarks(
      bufnr,
      -1,
      { row, col },
      { row, has_range and math.max(stop_col - 1, 0) or col },
      {
        details = true,
        overlap = true,
      }
    )
    local nsmap = namespace_map()
    local extmarks = vim.tbl_map(function(extmark)
      return extmark_to_map(extmark, nsmap)
    end, raw_extmarks)

    if not has_range and opts.extmarks ~= 'all' then
      extmarks = vim.tbl_filter(function(extmark)
        return overlaps_single_pos(extmark, row, col)
      end, extmarks)
    end

    if opts.semantic_tokens then
      result.semantic_tokens = vim.tbl_filter(function(extmark)
        return vim.startswith(extmark.ns, 'nvim.lsp.semantic_tokens')
      end, extmarks)
    end

    if opts.extmarks then
      result.extmarks = vim.tbl_filter(function(extmark)
        return not vim.startswith(extmark.ns, 'nvim.lsp.semantic_tokens')
          and (opts.extmarks == 'all' or extmark.hl_group ~= nil)
      end, extmarks)
    end
  end

  return result
end

return M
