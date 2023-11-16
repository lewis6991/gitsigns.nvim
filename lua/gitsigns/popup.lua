local M = {}

local api = vim.api

--- @param bufnr integer
--- @param lines string[]
--- @return integer
local function bufnr_calc_width(bufnr, lines)
  return api.nvim_buf_call(bufnr, function()
    local width = 0
    for _, l in ipairs(lines) do
      if vim.fn.type(l) == vim.v.t_string then
        local len = vim.fn.strdisplaywidth(l)
        if len > width then
          width = len
        end
      end
    end
    return width + 1 -- Add 1 for some miinor padding
  end)
end

-- Expand height until all lines are visible to account for wrapped lines.
--- @param winid integer
--- @param nlines integer
--- @param border string
local function expand_height(winid, nlines, border)
  local newheight = 0
  local maxheight = vim.o.lines - vim.o.cmdheight - (border ~= '' and 2 or 0)
  for _ = 0, 50 do
    local winheight = api.nvim_win_get_height(winid)
    if newheight > winheight then
      -- Window must be max height
      break
    end
    --- @type integer
    local wd = api.nvim_win_call(winid, function()
      return vim.fn.line('w$')
    end)
    if wd >= nlines then
      break
    end
    newheight = winheight + nlines - wd
    if newheight > maxheight then
      api.nvim_win_set_height(winid, maxheight)
      break
    end
    api.nvim_win_set_height(winid, newheight)
  end
end

--- @class (exact) Gitsigns.HlMark
--- @field hl_group string
--- @field start_row? integer
--- @field start_col? integer
--- @field end_row? integer
--- @field end_col? integer

--- Each element represents a multi-line segment
--- @alias Gitsigns.LineSpec { [1]: string, [2]: Gitsigns.HlMark[]}[][]

--- @param hlmarks Gitsigns.HlMark[]
--- @param row_offset integer
local function offset_hlmarks(hlmarks, row_offset)
  for _, h in ipairs(hlmarks) do
    h.start_row = (h.start_row or 0) + row_offset
    if h.end_row then
      h.end_row = h.end_row + row_offset
    end
  end
end

--- Partition the text and Gitsigns.HlMarks from a Gitsigns.LineSpec
--- @param fmt Gitsigns.LineSpec
--- @return string[]
--- @return Gitsigns.HlMark[]
local function partition_linesspec(fmt)
  local lines = {} --- @type string[]
  local ret = {} --- @type Gitsigns.HlMark[]

  local row = 0
  for _, section in ipairs(fmt) do
    local section_text = {} --- @type string[]
    local col = 0
    for _, part in ipairs(section) do
      local text, hls = part[1], part[2]

      section_text[#section_text + 1] = text

      local _, no_lines = text:gsub('\n', '')
      local end_row = row + no_lines --- @type integer
      local end_col = no_lines > 0 and 0 or col + #text --- @type integer

      if type(hls) == 'string' then
        ret[#ret + 1] = {
          hl_group = hls,
          start_row = row,
          end_row = end_row,
          start_col = col,
          end_col = end_col,
        }
      else -- hl is Gitsigns.HlMark[]
        offset_hlmarks(hls, row)
        vim.list_extend(ret, hls)
      end

      row = end_row
      col = end_col
    end

    local section_lines = vim.split(table.concat(section_text), '\n', { plain = true })
    vim.list_extend(lines, section_lines)

    row = row + 1
  end

  return lines, ret
end

--- @param id string|true
local function close_all_but(id)
  for _, winid in ipairs(api.nvim_list_wins()) do
    if vim.w[winid].gitsigns_preview ~= nil and vim.w[winid].gitsigns_preview ~= id then
      pcall(api.nvim_win_close, winid, true)
    end
  end
end

--- @param id string
function M.close(id)
  for _, winid in ipairs(api.nvim_list_wins()) do
    if vim.w[winid].gitsigns_preview == id then
      pcall(api.nvim_win_close, winid, true)
    end
  end
end

local ns = api.nvim_create_namespace('gitsigns_popup')

--- @param lines string[]
--- @param highlights Gitsigns.HlMark[]
--- @return integer bufnr
local function create_buf(lines, highlights)
  local ts = vim.bo.tabstop
  local bufnr = api.nvim_create_buf(false, true)
  assert(bufnr, 'Failed to create buffer')

  -- In case nvim was opened with '-M'
  vim.bo[bufnr].modifiable = true
  api.nvim_buf_set_lines(bufnr, 0, -1, true, lines)
  vim.bo[bufnr].modifiable = false

  -- Set tabstop before calculating the buffer width so that the correct width
  -- is calculated
  vim.bo[bufnr].tabstop = ts

  for _, hl in ipairs(highlights) do
    local ok, err = pcall(api.nvim_buf_set_extmark, bufnr, ns, hl.start_row, hl.start_col or 0, {
      hl_group = hl.hl_group,
      end_row = hl.end_row,
      end_col = hl.end_col,
      hl_eol = true,
    })
    if not ok then
      error(vim.inspect(hl) .. '\n' .. err)
    end
  end

  return bufnr
end

--- @param bufnr integer
--- @param opts table
--- @param id? string|true
--- @return integer winid
local function create_win(bufnr, opts, id)
  id = id or true

  -- Close any popups not matching id
  close_all_but(id)

  local lines = api.nvim_buf_get_lines(bufnr, 0, -1, true)

  local opts1 = vim.deepcopy(opts or {})
  opts1.height = opts1.height or #lines -- Guess, adjust later
  opts1.width = opts1.width or bufnr_calc_width(bufnr, lines)

  local winid = api.nvim_open_win(bufnr, false, opts1)

  vim.w[winid].gitsigns_preview = id

  if not opts.height then
    expand_height(winid, #lines, opts.border)
  end

  if opts1.style == 'minimal' then
    -- If 'signcolumn' = auto:1-2, then a empty signcolumn will appear and cause
    -- line wrapping.
    vim.wo[winid].signcolumn = 'no'
  end

  -- Close the popup when navigating to any window which is not the preview
  -- itself.
  local group = 'gitsigns_popup'
  local group_id = api.nvim_create_augroup(group, {})
  local old_cursor = api.nvim_win_get_cursor(0)

  api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
    group = group_id,
    callback = function()
      local cursor = api.nvim_win_get_cursor(0)
      -- Did the cursor REALLY change (neovim/neovim#12923)
      if
        (old_cursor[1] ~= cursor[1] or old_cursor[2] ~= cursor[2])
        and api.nvim_get_current_win() ~= winid
      then
        -- Clear the augroup
        api.nvim_create_augroup(group, {})
        pcall(api.nvim_win_close, winid, true)
        return
      end
      old_cursor = cursor
    end,
  })

  api.nvim_create_autocmd('WinClosed', {
    pattern = tostring(winid),
    group = group_id,
    callback = function()
      -- Clear the augroup
      api.nvim_create_augroup(group, {})
    end,
  })

  -- update window position to follow the cursor when scrolling
  api.nvim_create_autocmd('WinScrolled', {
    buffer = api.nvim_get_current_buf(),
    group = group_id,
    callback = function()
      if api.nvim_win_is_valid(winid) then
        api.nvim_win_set_config(winid, opts1)
      end
    end,
  })

  return winid
end

--- @param lines_spec {[1]: string, [2]: string|Gitsigns.HlMark[]}[][]
--- @param opts table
--- @param id? string
--- @return integer winid, integer bufnr
function M.create(lines_spec, opts, id)
  local lines, highlights = partition_linesspec(lines_spec)
  local bufnr = create_buf(lines, highlights)
  local winid = create_win(bufnr, opts, id)
  return winid, bufnr
end

--- @param id string
--- @return integer? winid
function M.is_open(id)
  for _, winid in ipairs(api.nvim_list_wins()) do
    if vim.w[winid].gitsigns_preview == id then
      return winid
    end
  end
end

--- @param id string
--- @return integer? winid
function M.focus_open(id)
  local winid = M.is_open(id)
  if winid then
    api.nvim_set_current_win(winid)
  end
  return winid
end

return M
