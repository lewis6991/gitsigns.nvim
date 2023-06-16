local a = require('gitsigns.async')
local wrap = a.wrap
local void = a.void
local scheduler = a.scheduler

local cache = require('gitsigns.cache').cache
local config = require('gitsigns.config').config
local util = require('gitsigns.util')
local uv = vim.loop

local api = vim.api

local current_buf = api.nvim_get_current_buf

local namespace = api.nvim_create_namespace('gitsigns_blame')

local timer = assert(uv.new_timer())

local M = {}

local wait_timer = wrap(uv.timer_start, 4)

--- @param bufnr integer
--- @param row integer
--- @param opts? table
local function set_extmark(bufnr, row, opts)
  opts = opts or {}
  opts.id = 1
  api.nvim_buf_set_extmark(bufnr, namespace, row - 1, 0, opts)
end

--- @param bufnr integer
--- @return integer? id
local function get_extmark(bufnr)
  local pos = api.nvim_buf_get_extmark_by_id(bufnr, namespace, 1, {})
  if pos[1] then
    return pos[1] + 1
  end
end

--- @param bufnr? integer
local function reset(bufnr)
  bufnr = bufnr or current_buf()
  if not api.nvim_buf_is_valid(bufnr) then
    return
  end
  api.nvim_buf_del_extmark(bufnr, namespace, 1)
  vim.b[bufnr].gitsigns_blame_line_dict = nil
end

-- TODO: expose as config
local max_cache_size = 1000

--- @class Gitsigns.BlameCache
--- @field cache table<integer,Gitsigns.BlameInfo>
--- @field size integer
--- @field tick integer

local BlameCache = {}

--- @type table<integer,Gitsigns.BlameCache>
BlameCache.contents = {}

--- @param bufnr integer
--- @param lnum integer
--- @param x? Gitsigns.BlameInfo
function BlameCache:add(bufnr, lnum, x)
  if not x then
    return
  end
  if not config._blame_cache then
    return
  end
  local scache = self.contents[bufnr]
  if scache.size <= max_cache_size then
    scache.cache[lnum] = x
    scache.size = scache.size + 1
  end
end

--- @param bufnr integer
--- @param lnum integer
--- @return Gitsigns.BlameInfo?
function BlameCache:get(bufnr, lnum)
  if not config._blame_cache then
    return
  end

  -- init and invalidate
  local tick = vim.b[bufnr].changedtick
  if not self.contents[bufnr] or self.contents[bufnr].tick ~= tick then
    self.contents[bufnr] = { tick = tick, cache = {}, size = 0 }
  end

  return self.contents[bufnr].cache[lnum]
end

--- @param fmt string
--- @param name string
--- @param info Gitsigns.BlameInfo
--- @return string
local function expand_blame_format(fmt, name, info)
  if info.author == name then
    info.author = 'You'
  end
  return util.expand_format(fmt, info, config.current_line_blame_formatter_opts.relative_time)
end

--- @param virt_text {[1]: string, [2]: string}[]
--- @return string
local function flatten_virt_text(virt_text)
  local res = {} ---@type string[]
  for _, part in ipairs(virt_text) do
    res[#res + 1] = part[1]
  end
  return table.concat(res)
end

-- Update function, must be called in async context
local update = void(function()
  local bufnr = current_buf()
  local lnum = api.nvim_win_get_cursor(0)[1]

  local old_lnum = get_extmark(bufnr)
  if old_lnum and lnum == old_lnum and BlameCache:get(bufnr, lnum) then
    -- Don't update if on the same line and we already have results
    return
  end

  if api.nvim_get_mode().mode == 'i' then
    reset(bufnr)
    return
  end

  -- Set an empty extmark to save the line number.
  -- This will also clear virt_text.
  -- Only do this if there was already an extmark to avoid clearing the intro
  -- text.
  if get_extmark(bufnr) then
    reset(bufnr)
    set_extmark(bufnr, lnum)
  end

  -- Can't show extmarks on folded lines so skip
  if vim.fn.foldclosed(lnum) ~= -1 then
    return
  end

  local opts = config.current_line_blame_opts

  -- Note because the same timer is re-used, this call has a debouncing effect.
  wait_timer(timer, opts.delay, 0)
  scheduler()

  local bcache = cache[bufnr]
  if not bcache or not bcache.git_obj.object_name then
    return
  end

  local result = BlameCache:get(bufnr, lnum)
  if not result then
    local buftext = util.buf_lines(bufnr)
    result = bcache.git_obj:run_blame(buftext, lnum, opts.ignore_whitespace)
    BlameCache:add(bufnr, lnum, result)
    scheduler()
  end

  local lnum1 = api.nvim_win_get_cursor(0)[1]
  if bufnr == current_buf() and lnum ~= lnum1 then
    -- Cursor has moved during events; abort
    return
  end

  if not api.nvim_buf_is_loaded(bufnr) then
    -- Buffer is no longer loaded; abort
    return
  end

  vim.b[bufnr].gitsigns_blame_line_dict = result

  if result then
    local virt_text ---@type {[1]: string, [2]: string}[]
    local clb_formatter = result.author == 'Not Committed Yet'
        and config.current_line_blame_formatter_nc
      or config.current_line_blame_formatter
    if type(clb_formatter) == 'string' then
      virt_text = {
        {
          expand_blame_format(clb_formatter, bcache.git_obj.repo.username, result),
          'GitSignsCurrentLineBlame',
        },
      }
    else -- function
      virt_text = clb_formatter(
        bcache.git_obj.repo.username,
        result,
        config.current_line_blame_formatter_opts
      )
    end

    vim.b[bufnr].gitsigns_blame_line = flatten_virt_text(virt_text)

    if opts.virt_text then
      set_extmark(bufnr, lnum, {
        virt_text = virt_text,
        virt_text_pos = opts.virt_text_pos,
        priority = opts.virt_text_priority,
        hl_mode = 'combine',
      })
    end
  end
end)

function M.setup()
  local group = api.nvim_create_augroup('gitsigns_blame', {})

  for k, _ in pairs(cache) do
    reset(k)
  end

  if config.current_line_blame then
    api.nvim_create_autocmd({ 'FocusGained', 'BufEnter', 'CursorMoved', 'CursorMovedI' }, {
      group = group,
      callback = function()
        update()
      end,
    })

    api.nvim_create_autocmd({ 'InsertEnter', 'FocusLost', 'BufLeave' }, {
      group = group,
      callback = function()
        reset()
      end,
    })

    -- Call via vim.schedule to avoid the debounce timer killing the async
    -- coroutine
    vim.schedule(update)
  end
end

return M
