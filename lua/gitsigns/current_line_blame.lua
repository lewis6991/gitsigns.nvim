local async = require('gitsigns.async')
local cache = require('gitsigns.cache').cache
local config = require('gitsigns.config').config
local util = require('gitsigns.util')

local api = vim.api

local debounce = require('gitsigns.debounce')

local namespace = api.nvim_create_namespace('gitsigns_blame')

local M = {}

--- @param bufnr integer
local function reset(bufnr)
  if not api.nvim_buf_is_valid(bufnr) then
    return
  end
  api.nvim_buf_del_extmark(bufnr, namespace, 1)
  vim.b[bufnr].gitsigns_blame_line_dict = nil
end

--- @class (exact) Gitsigns.BlameCache
--- @field cache Gitsigns.BlameInfo[]?
--- @field tick integer

--- @type table<integer,Gitsigns.BlameCache>
local blame_cache = {}

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

--- @param bufnr integer
--- @param lnum integer
--- @param opts Gitsigns.CurrentLineBlameOpts
--- @return Gitsigns.BlameInfo?
local function run_blame(bufnr, lnum, opts)
  -- init and invalidate
  local tick = vim.b[bufnr].changedtick
  if not blame_cache[bufnr] or blame_cache[bufnr].tick ~= tick then
    blame_cache[bufnr] = { tick = tick }
  end

  local result = blame_cache[bufnr].cache

  if result then
    return result[lnum]
  end

  local buftext = util.buf_lines(bufnr)
  local bcache = cache[bufnr]
  result = bcache.git_obj:run_blame(buftext, nil, opts.ignore_whitespace)

  if not result then
    return
  end

  blame_cache[bufnr].cache = result

  return result[lnum]
end

--- @param bufnr integer
--- @param lnum integer
--- @param blame_info Gitsigns.BlameInfo
--- @param opts Gitsigns.CurrentLineBlameOpts
local function handle_blame_info(bufnr, lnum, blame_info, opts)
  blame_info = util.convert_blame_info(blame_info)

  vim.b[bufnr].gitsigns_blame_line_dict = blame_info

  local bcache = assert(cache[bufnr])
  local virt_text ---@type {[1]: string, [2]: string}[]
  local clb_formatter = blame_info.author == 'Not Committed Yet'
      and config.current_line_blame_formatter_nc
    or config.current_line_blame_formatter
  if type(clb_formatter) == 'string' then
    virt_text = {
      {
        expand_blame_format(clb_formatter, bcache.git_obj.repo.username, blame_info),
        'GitSignsCurrentLineBlame',
      },
    }
  else -- function
    virt_text = clb_formatter(
      bcache.git_obj.repo.username,
      blame_info,
      config.current_line_blame_formatter_opts
    )
  end

  vim.b[bufnr].gitsigns_blame_line = flatten_virt_text(virt_text)

  if opts.virt_text then
    api.nvim_buf_set_extmark(bufnr, namespace, lnum - 1, 0, {
      id = 1,
      virt_text = virt_text,
      virt_text_pos = opts.virt_text_pos,
      priority = opts.virt_text_priority,
      hl_mode = 'combine',
    })
  end
end

--- @param winid integer
--- @return integer lnum
local function get_lnum(winid)
  return api.nvim_win_get_cursor(winid)[1]
end

--- @param winid integer
--- @param lnum integer
--- @return boolean
local function foldclosed(winid, lnum)
  ---@return boolean
  return api.nvim_win_call(winid, function()
    return vim.fn.foldclosed(lnum) ~= -1
  end)
end

---@return boolean
local function insert_mode()
  return api.nvim_get_mode().mode == 'i'
end

--- Update function, must be called in async context
--- @param bufnr integer
local function update0(bufnr)
  async.scheduler_if_buf_valid(bufnr)

  if insert_mode() then
    return
  end

  local winid = vim.fn.bufwinid(bufnr)
  if winid == -1 then
    return
  end

  local lnum = get_lnum(winid)

  -- Can't show extmarks on folded lines so skip
  if foldclosed(winid, lnum) then
    return
  end

  local bcache = cache[bufnr]
  if not bcache or not bcache.git_obj.object_name then
    return
  end

  local opts = config.current_line_blame_opts

  local blame_info = run_blame(bufnr, lnum, opts)

  if not blame_info then
    return
  end

  async.scheduler_if_buf_valid(bufnr)

  if lnum ~= get_lnum(winid) then
    -- Cursor has moved during events; abort and tr-trigger another update
    update0(bufnr)
    return
  end

  handle_blame_info(bufnr, lnum, blame_info, opts)
end

local update = async.void(debounce.throttle_by_id(update0))

--- @type fun(bufnr: integer)
local update_debounced

function M.setup()
  local group = api.nvim_create_augroup('gitsigns_blame', {})

  local opts = config.current_line_blame_opts
  update_debounced = debounce.debounce_trailing(opts.delay, update)

  for k, _ in pairs(cache) do
    reset(k)
  end

  if config.current_line_blame then
    api.nvim_create_autocmd({ 'FocusGained', 'BufEnter', 'CursorMoved', 'CursorMovedI' }, {
      group = group,
      callback = function(args)
        reset(args.buf)
        update_debounced(args.buf)
      end
    })

    api.nvim_create_autocmd({ 'InsertEnter', 'FocusLost', 'BufLeave' }, {
      group = group,
      callback = function(args)
        reset(args.buf)
      end,
    })

    update_debounced(api.nvim_get_current_buf())
  end
end

return M
