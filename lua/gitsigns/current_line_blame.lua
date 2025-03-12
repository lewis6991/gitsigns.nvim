local async = require('gitsigns.async')
local debounce = require('gitsigns.debounce')
local util = require('gitsigns.util')

local cache = require('gitsigns.cache').cache
local config = require('gitsigns.config').config
local schema = require('gitsigns.config').schema
local error_once = require('gitsigns.message').error_once

local api = vim.api

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

--- @param fmt string
--- @param name string
--- @param info Gitsigns.BlameInfoPublic
--- @return string
local function expand_blame_format(fmt, name, info)
  if info.author == name then
    info.author = 'You'
  end
  return util.expand_format(fmt, info)
end

--- @param virt_text [string, string][]
--- @return string
local function flatten_virt_text(virt_text)
  local res = {} ---@type string[]
  for _, part in ipairs(virt_text) do
    res[#res + 1] = part[1]
  end
  return table.concat(res)
end

--- @return integer
local function win_width()
  local winid = api.nvim_get_current_win()
  local wininfo = vim.fn.getwininfo(winid)[1]
  local textoff = wininfo and wininfo.textoff or 0
  return api.nvim_win_get_width(winid) - textoff
end

--- @param bufnr integer
--- @param lnum integer
--- @return integer
local function line_len(bufnr, lnum)
  local line = api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, true)[1]
  return api.nvim_strwidth(line)
end

--- @param fmt string
--- @return Gitsigns.CurrentLineBlameFmtFun
local function default_formatter(fmt)
  return function(username, blame_info)
    return {
      {
        expand_blame_format(fmt, username, blame_info),
        'GitSignsCurrentLineBlame',
      },
    }
  end
end

---@param bufnr integer
---@param blame_info Gitsigns.BlameInfoPublic
---@return [string, string][]
local function get_blame_virt_text(bufnr, blame_info)
  local git_obj = assert(cache[bufnr]).git_obj
  local use_nc = blame_info.author == 'Not Committed Yet'

  local clb_formatter = use_nc and config.current_line_blame_formatter_nc
    or config.current_line_blame_formatter

  if type(clb_formatter) == 'function' then
    local ok, res = pcall(clb_formatter, git_obj.repo.username, blame_info)
    if ok then
      return res
    end

    local nc_sfx = use_nc and '_nc' or ''
    error_once(
      'Failed running config.current_line_blame_formatter%s, using default:\n   %s',
      nc_sfx,
      res
    )
    --- @type string
    clb_formatter = schema.current_line_blame_formatter.default
  end

  return default_formatter(clb_formatter)(git_obj.repo.username, blame_info)
end

--- @param bufnr integer
--- @param lnum integer
--- @param blame_info Gitsigns.BlameInfo
--- @param opts Gitsigns.CurrentLineBlameOpts
local function handle_blame_info(bufnr, lnum, blame_info, opts)
  blame_info = util.convert_blame_info(blame_info)

  local virt_text = get_blame_virt_text(bufnr, blame_info)
  local virt_text_str = flatten_virt_text(virt_text)

  vim.b[bufnr].gitsigns_blame_line_dict = blame_info
  vim.b[bufnr].gitsigns_blame_line = virt_text_str

  if opts.virt_text then
    local virt_text_pos = opts.virt_text_pos
    if virt_text_pos == 'right_align' then
      if api.nvim_strwidth(virt_text_str) > (win_width() - line_len(bufnr, lnum)) then
        virt_text_pos = 'eol'
      end
    end
    api.nvim_buf_set_extmark(bufnr, namespace, lnum - 1, 0, {
      id = 1,
      virt_text = virt_text,
      virt_text_pos = virt_text_pos,
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
  async.schedule()
  if not api.nvim_buf_is_valid(bufnr) then
    return
  end

  if insert_mode() then
    return
  end

  local winid = api.nvim_get_current_win()

  if bufnr ~= api.nvim_win_get_buf(winid) then
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

  local blame_info = bcache:get_blame(lnum, opts)

  if not api.nvim_win_is_valid(winid) or bufnr ~= api.nvim_win_get_buf(winid) then
    return
  end

  if not blame_info then
    return
  end

  if lnum ~= get_lnum(winid) then
    -- Cursor has moved during events; abort and tr-trigger another update
    update0(bufnr)
    return
  end

  handle_blame_info(bufnr, lnum, blame_info, opts)
end

local update = async.create(1, debounce.throttle_by_id(update0))

--- @type fun(bufnr: integer)
M.update = nil

function M.setup()
  for k in pairs(cache) do
    reset(k)
  end

  local group = api.nvim_create_augroup('gitsigns_blame', {})

  if not config.current_line_blame then
    return
  end

  local opts = config.current_line_blame_opts
  -- TODO(lewis6991): opts.delay is always defined as the schema set
  -- deep_extend=true
  M.update = debounce.debounce_trailing(assert(opts.delay), update)

  -- show current buffer line blame immediately
  M.update(api.nvim_get_current_buf())

  local update_events = { 'BufEnter', 'CursorMoved', 'CursorMovedI' }
  local reset_events = { 'InsertEnter', 'BufLeave' }
  if vim.fn.exists('#WinResized') == 1 then
    -- For nvim 0.9+
    update_events[#update_events + 1] = 'WinResized'
  end
  if opts.use_focus then
    update_events[#update_events + 1] = 'FocusGained'
    reset_events[#reset_events + 1] = 'FocusLost'
  end

  api.nvim_create_autocmd(update_events, {
    group = group,
    callback = function(args)
      reset(args.buf)
      M.update(args.buf)
    end,
  })

  api.nvim_create_autocmd(reset_events, {
    group = group,
    callback = function(args)
      reset(args.buf)
    end,
  })

  api.nvim_create_autocmd('OptionSet', {
    group = group,
    pattern = { 'fileformat', 'bomb', 'eol' },
    callback = function(args)
      reset(args.buf)
    end,
  })
end

return M
