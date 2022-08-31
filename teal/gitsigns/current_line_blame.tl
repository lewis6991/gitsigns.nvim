local a = require('gitsigns.async')
local wrap      = a.wrap
local void      = a.void
local scheduler = a.scheduler

local cache     = require('gitsigns.cache').cache
local config    = require('gitsigns.config').config
local BlameInfo = require('gitsigns.git').BlameInfo
local util      = require('gitsigns.util')
local nvim      = require('gitsigns.nvim')
local uv        = require('gitsigns.uv')

local api = vim.api

local current_buf = api.nvim_get_current_buf

local namespace = api.nvim_create_namespace('gitsigns_blame')

local timer = uv.new_timer(true) as vim.loop.Timer

local record M
  setup: function()
end

local wait_timer = wrap(vim.loop.timer_start, 4)

local function set_extmark(bufnr: integer, row: integer, opts: {string:any})
  opts = opts or {}
  opts.id = 1
  api.nvim_buf_set_extmark(bufnr, namespace, row-1, 0, opts)
end

local function get_extmark(bufnr: integer): integer
  local pos = api.nvim_buf_get_extmark_by_id(bufnr, namespace, 1, {}) as {integer, integer}
  if pos[1] then
    return pos[1] + 1
  end
  return
end

local reset = function(bufnr: integer)
  bufnr = bufnr or current_buf()
  api.nvim_buf_del_extmark(bufnr, namespace, 1)
  pcall(api.nvim_buf_del_var, bufnr, 'gitsigns_blame_line_dict')
end

-- TODO: expose as config
local max_cache_size = 1000

local record BlameCache
  record Elem
    tick: integer
    cache: {integer:BlameInfo}
    size: integer
  end
  contents: {integer:Elem}
end

BlameCache.contents = {}

function BlameCache:add(bufnr: integer, lnum: integer, x: BlameInfo)
  if not config._blame_cache then return end
  local scache = self.contents[bufnr]
  if scache.size <= max_cache_size then
    scache.cache[lnum] = x
    scache.size = scache.size + 1
  end
end

function BlameCache:get(bufnr: integer, lnum: integer): BlameInfo
  if not config._blame_cache then return end

  -- init and invalidate
  local tick = vim.b[bufnr].changedtick
  if not self.contents[bufnr] or self.contents[bufnr].tick ~= tick then
    self.contents[bufnr] = {tick = tick, cache = {}, size = 0}
  end

  return self.contents[bufnr].cache[lnum]
end

local function expand_blame_format(fmt: string, name: string, info: BlameInfo): string
  if info.author == name then
    info.author = 'You'
  end
  return util.expand_format(fmt, info, config.current_line_blame_formatter_opts.relative_time)
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

  api.nvim_buf_set_var(bufnr, 'gitsigns_blame_line_dict', result)
  if opts.virt_text and result then
    local virt_text: {{string, string}}
    local clb_formatter = result.author == 'Not Committed Yet' and
      config.current_line_blame_formatter_nc or
      config.current_line_blame_formatter
    if clb_formatter is string then
      virt_text = {{
        expand_blame_format(clb_formatter, bcache.git_obj.repo.username, result),
        'GitSignsCurrentLineBlame'
      }}
    else -- function
      virt_text = clb_formatter(
        bcache.git_obj.repo.username,
        result,
        config.current_line_blame_formatter_opts
      )
    end

    set_extmark(bufnr, lnum, {
      virt_text     = virt_text,
      virt_text_pos = opts.virt_text_pos,
      priority      = opts.virt_text_priority,
      hl_mode       = 'combine',
    })
  end
end)

M.setup = function()
  nvim.augroup('gitsigns_blame')

  for k, _ in pairs(cache as {integer:any}) do
    reset(k)
  end

  if config.current_line_blame then
    nvim.autocmd(
      {'FocusGained', 'BufEnter', 'CursorMoved', 'CursorMovedI'},
      { group = 'gitsigns_blame', callback = function() update() end }
    )

    nvim.autocmd(
      {'InsertEnter', 'FocusLost', 'BufLeave'},
      { group = 'gitsigns_blame', callback = function() reset() end }
    )

    -- Call via vim.schedule to avoid the debounce timer killing the async
    -- coroutine
    vim.schedule(update)
  end
end

return M
