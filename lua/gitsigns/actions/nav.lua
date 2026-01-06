local async = require('gitsigns.async')
local Hunks = require('gitsigns.hunks')
local cache = require('gitsigns.cache').cache
local Popup = require('gitsigns.popup')

local api = vim.api

--- @class Gitsigns.NavOpts
--- Whether to loop around file or not. Defaults
--- to the value 'wrapscan'
--- @field wrap boolean
--- Expand folds when navigating to a hunk which is
--- inside a fold. Defaults to `true` if 'foldopen'
--- contains `search`.
--- @field foldopen boolean
--- Whether to show navigation messages or not.
--- Looks at 'shortmess' for default behaviour.
--- @field navigation_message boolean
--- Only navigate between non-contiguous hunks. Only useful if
--- 'diff_opts' contains `linematch`. Defaults to `true`.
--- @field greedy boolean
--- Automatically open preview_hunk() upon navigating
--- to a hunk.
--- @field preview? boolean
--- Number of times to advance. Defaults to |v:count1|.
--- @field count integer
--- Which kinds of hunks to target. Defaults to `'unstaged'`.
--- @field target 'unstaged'|'staged'|'all'

--- @class gitsigns.nav
local M = {}

--- @param x string
--- @param word string
--- @return boolean
local function findword(x, word)
  return string.find(x, '%f[%w_]' .. word .. '%f[^%w_]') ~= nil
end

--- @param opts? Gitsigns.NavOpts
--- @return Gitsigns.NavOpts
local function process_nav_opts(opts)
  opts = opts or {}

  -- show navigation message
  if opts.navigation_message == nil then
    opts.navigation_message = vim.o.shortmess:find('S') == nil
  end

  -- wrap around
  if opts.wrap == nil then
    opts.wrap = vim.o.wrapscan
  end

  if opts.foldopen == nil then
    opts.foldopen = findword(vim.o.foldopen, 'search')
  end

  if opts.greedy == nil then
    opts.greedy = true
  end

  if opts.count == nil then
    opts.count = vim.v.count1
  end

  if opts.target == nil then
    opts.target = 'unstaged'
  end

  return opts
end

--- @async
--- @param bufnr integer
--- @param target 'unstaged'|'staged'|'all'
--- @param greedy boolean
--- @return Gitsigns.Hunk.Hunk[]
local function get_nav_hunks(bufnr, target, greedy)
  local bcache = assert(cache[bufnr])
  local hunks_main = bcache:get_hunks(greedy, false) or {}

  local hunks --- @type Gitsigns.Hunk.Hunk[]
  if target == 'unstaged' then
    hunks = hunks_main
  else
    local hunks_head = bcache:get_hunks(greedy, true) or {}
    hunks_head = Hunks.filter_common(hunks_head, hunks_main) or {}
    if target == 'all' then
      hunks = hunks_main
      vim.list_extend(hunks, hunks_head)
      table.sort(hunks, function(h1, h2)
        return h1.added.start < h2.added.start
      end)
    elseif target == 'staged' then
      hunks = hunks_head
    end
  end
  return hunks
end

--- @async
--- @param direction 'first'|'last'|'next'|'prev'
--- @param opts? Gitsigns.NavOpts
function M.nav_hunk(direction, opts)
  opts = process_nav_opts(opts)
  local bufnr = api.nvim_get_current_buf()
  local bcache = cache[bufnr]
  if not bcache then
    return
  end

  local hunks = get_nav_hunks(bufnr, opts.target, opts.greedy)

  if not hunks or vim.tbl_isempty(hunks) then
    if opts.navigation_message then
      api.nvim_echo({ { 'No hunks', 'WarningMsg' } }, false, {})
    end
    return
  end

  local line = api.nvim_win_get_cursor(0)[1] --[[@as integer]]
  local index --- @type integer?

  local forwards = direction == 'next' or direction == 'last'

  for _ = 1, opts.count do
    index = Hunks.find_nearest_hunk(line, hunks, direction, opts.wrap)

    if not index then
      if opts.navigation_message then
        api.nvim_echo({ { 'No more hunks', 'WarningMsg' } }, false, {})
      end
      local _, col = vim.fn.getline(line):find('^%s*')
      --- @cast col -?
      api.nvim_win_set_cursor(0, { line, col })
      return
    end
    local hunk = assert(hunks[index])
    line = forwards and hunk.added.start or hunk.vend
  end

  -- Check if preview popup is open before moving the cursor
  local should_preview = opts.preview or Popup.is_open('hunk') ~= nil

  -- Handle topdelete
  line = math.max(line, 1)

  vim.cmd([[ normal! m' ]]) -- add current cursor position to the jump list

  local _, col = vim.fn.getline(line):find('^%s*')
  --- @cast col -?
  api.nvim_win_set_cursor(0, { line, col })

  if opts.foldopen then
    vim.cmd('silent! foldopen!')
  end

  -- schedule so the cursor change can settle, otherwise the popup might
  -- appear in the old position
  async.schedule()

  local Preview = require('gitsigns.actions.preview')

  if should_preview then
    -- Close the popup in case one is open which will cause it to focus the
    -- popup
    Popup.close('hunk')
    Preview.preview_hunk()
  elseif Preview.has_preview_inline(bufnr) then
    Preview.preview_hunk_inline()
  end

  if index and opts.navigation_message then
    api.nvim_echo({ { ('Hunk %d of %d'):format(index, #hunks), 'None' } }, false, {})
  end
end

return M
