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
local function expand_height(winid, nlines)
  local newheight = 0
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
    api.nvim_win_set_height(winid, newheight)
  end
end

local function offset_hlmarks(hlmarks, row_offset)
  for _, h in ipairs(hlmarks) do
    if h.start_row then
      h.start_row = h.start_row + row_offset
    end
    if h.end_row then
      h.end_row = h.end_row + row_offset
    end
  end
end

--- @param fmt {[1]: string, [2]: string}[][]
local function process_linesspec(fmt)
  local lines = {} --- @type string[]
  local hls = {}

  local row = 0
  for _, section in ipairs(fmt) do
    local sec = {} --- @type string[]
    local pos = 0
    for _, part in ipairs(section) do
      local text = part[1]
      local hl = part[2]

      sec[#sec + 1] = text

      local srow = row
      local scol = pos

      local ts = vim.split(text, '\n')

      if #ts > 1 then
        pos = 0
        row = row + #ts - 1
      else
        pos = pos + #text
      end

      if type(hl) == 'string' then
        hls[#hls + 1] = {
          hl_group = hl,
          start_row = srow,
          end_row = row,
          start_col = scol,
          end_col = pos,
        }
      else -- hl is {HlMark}
        offset_hlmarks(hl, srow)
        vim.list_extend(hls, hl)
      end
    end
    for _, l in ipairs(vim.split(table.concat(sec, ''), '\n')) do
      lines[#lines + 1] = l
    end
    row = row + 1
  end

  return lines, hls
end

local function close_all_but(id)
  for _, winid in ipairs(api.nvim_list_wins()) do
    if vim.w[winid].gitsigns_preview ~= nil and vim.w[winid].gitsigns_preview ~= id then
      pcall(api.nvim_win_close, winid, true)
    end
  end
end

function M.close(id)
  for _, winid in ipairs(api.nvim_list_wins()) do
    if vim.w[winid].gitsigns_preview == id then
      pcall(api.nvim_win_close, winid, true)
    end
  end
end

function M.create0(lines, opts, id)
  -- Close any popups not matching id
  close_all_but(id)

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

  local opts1 = vim.deepcopy(opts or {})
  opts1.height = opts1.height or #lines -- Guess, adjust later
  opts1.width = opts1.width or bufnr_calc_width(bufnr, lines)

  local winid = api.nvim_open_win(bufnr, false, opts1)

  vim.w[winid].gitsigns_preview = id or true

  if not opts.height then
    expand_height(winid, #lines)
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

  return winid, bufnr
end

local ns = api.nvim_create_namespace('gitsigns_popup')

function M.create(lines_spec, opts, id)
  local lines, highlights = process_linesspec(lines_spec)
  local winid, bufnr = M.create0(lines, opts, id)

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

  return winid, bufnr
end

function M.is_open(id)
  for _, winid in ipairs(api.nvim_list_wins()) do
    if vim.w[winid].gitsigns_preview == id then
      return winid
    end
  end
  return nil
end

function M.focus_open(id)
  local winid = M.is_open(id)
  if winid then
    api.nvim_set_current_win(winid)
  end
  return winid
end

return M
