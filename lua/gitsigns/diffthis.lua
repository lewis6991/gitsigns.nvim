local async = require('gitsigns.async')
local manager = require('gitsigns.manager')
local message = require('gitsigns.message')
local util = require('gitsigns.util')
local Status = require('gitsigns.status')

local cache = require('gitsigns.cache').cache
local log = require('gitsigns.debug.log')
local throttle_by_id = require('gitsigns.debounce').throttle_by_id

local api = vim.api

local M = {}

--- @async
--- @param bufnr integer
--- @param dbufnr integer
--- @param base string?
local function bufread(bufnr, dbufnr, base)
  local bcache = assert(cache[bufnr])
  base = util.norm_base(base)
  local text --- @type string[]
  if base == bcache.git_obj.revision then
    text = assert(bcache.compare_text)
  else
    local err
    text, err = bcache.git_obj:get_show_text(base)
    if err then
      error(err, 2)
    end
    async.schedule()
    if not api.nvim_buf_is_valid(bufnr) then
      return
    end
  end

  vim.bo[dbufnr].fileformat = vim.bo[bufnr].fileformat
  vim.bo[dbufnr].filetype = vim.bo[bufnr].filetype
  vim.bo[dbufnr].bufhidden = 'wipe'

  local modifiable = vim.bo[dbufnr].modifiable
  vim.bo[dbufnr].modifiable = true
  Status:update(dbufnr, { head = base })

  util.set_lines(dbufnr, 0, -1, text)

  vim.bo[dbufnr].modifiable = modifiable
  vim.bo[dbufnr].modified = false
  require('gitsigns.attach').attach(dbufnr, nil, 'BufReadCmd')
end

--- @async
--- @param bufnr integer
--- @param dbufnr integer
--- @param base string?
local function bufwrite(bufnr, dbufnr, base)
  local bcache = assert(cache[bufnr])
  local buftext = util.buf_lines(dbufnr)
  base = util.norm_base(base)
  bcache.git_obj:stage_lines(buftext)
  async.schedule()
  if not api.nvim_buf_is_valid(bufnr) then
    return
  end
  vim.bo[dbufnr].modified = false
  -- If diff buffer base matches the git_obj revision then also update the
  -- signs.
  if base == bcache.git_obj.revision then
    bcache.compare_text = buftext
    manager.update(bufnr)
  end
end

--- @async
--- Create a gitsigns buffer for a certain revision of a file
--- @param bufnr integer
--- @param base string?
--- @return string? buf Buffer name
--- @return integer? bufnr Buffer number
local function create_revision_buf(bufnr, base)
  local bcache = assert(cache[bufnr])
  base = util.norm_base(base)

  local bufname = bcache:get_rev_bufname(base)

  if util.bufexists(bufname) then
    return bufname, vim.fn.bufnr(bufname)
  end

  local dbuf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_name(dbuf, bufname)

  local ok, err = pcall(bufread, bufnr, dbuf, base)
  if not ok then
    message.error(err --[[@as string]])
    async.schedule()
    api.nvim_buf_delete(dbuf, { force = true })
    return
  end

  -- allow editing the index revision
  if not base then
    vim.bo[dbuf].buftype = 'acwrite'

    api.nvim_create_autocmd('BufReadCmd', {
      group = 'gitsigns',
      buffer = dbuf,
      callback = function()
        async.arun(bufread, bufnr, dbuf, base):raise_on_error()
      end,
    })

    api.nvim_create_autocmd('BufWriteCmd', {
      group = 'gitsigns',
      buffer = dbuf,
      callback = function()
        async.arun(bufwrite, bufnr, dbuf, base):raise_on_error()
      end,
    })
  else
    vim.bo[dbuf].buftype = 'nowrite'
    vim.bo[dbuf].modifiable = false
  end

  return bufname, dbuf
end

--- @class Gitsigns.DiffthisOpts
--- @field vertical? boolean
--- @field split? string

--- @async
--- @param base string?
--- @param opts? Gitsigns.DiffthisOpts
local function diffthis_rev(base, opts)
  local bufnr = api.nvim_get_current_buf()

  local bufname, dbuf = create_revision_buf(bufnr, base)
  if not bufname then
    return
  end

  opts = opts or {}

  local cwin = api.nvim_get_current_win()

  vim.cmd.diffsplit({
    bufname,
    mods = {
      vertical = opts.vertical,
      split = opts.split or 'aboveleft',
      keepalt = true,
    },
  })

  api.nvim_set_current_win(cwin)

  -- Reset 'diff' option for the current window if the diff buffer is hidden
  api.nvim_create_autocmd('BufHidden', {
    buffer = assert(dbuf),
    callback = function()
      local tabpage = api.nvim_win_get_tabpage(cwin)

      local disable_cwin_diff = true
      for _, w in ipairs(api.nvim_tabpage_list_wins(tabpage)) do
        if w ~= cwin and vim.wo[w].diff then
          -- If there is another diff window open, don't disable diff
          disable_cwin_diff = false
          break
        end
      end

      if disable_cwin_diff then
        vim.wo[cwin].diff = false
      end
    end,
  })
end

--- @param base string?
--- @param opts Gitsigns.DiffthisOpts
--- @param _callback? fun()
M.diffthis = async.create(2, function(base, opts, _callback)
  if vim.wo.diff then
    log.dprint('diff is disabled')
    return
  end

  local bufnr = api.nvim_get_current_buf()
  local bcache = cache[bufnr]
  if not bcache then
    log.dprintf('buffer %d is not attached', bufnr)
    return
  end

  if not base and bcache.git_obj.has_conflicts then
    diffthis_rev(':2', opts)
    opts.split = 'belowright'
    diffthis_rev(':3', opts)
  else
    diffthis_rev(base, opts)
  end
end)

--- @param bufnr integer
--- @param base string
--- @param _callback? fun()
M.show = async.create(2, function(bufnr, base, _callback)
  __FUNC__ = 'show'
  local bufname = create_revision_buf(bufnr, base)
  if not bufname then
    log.dprint('No bufname for revision ' .. base)
    return
  end

  log.dprint('bufname ' .. bufname)
  vim.cmd.edit(bufname)

  -- Wait for the buffer to attach in case the user passes a callback that
  -- requires the buffer to be attached.
  local sbufnr = api.nvim_get_current_buf()

  local attached = vim.wait(2000, function()
    return cache[sbufnr] ~= nil
  end)

  if not attached then
    log.eprintf("Show buffer '%s' did not attach", bufname)
  end
end)

--- @async
--- @param bufnr integer
--- @return boolean
local function should_reload(bufnr)
  if not vim.bo[bufnr].modified then
    return true
  end
  local response --- @type string?
  while not vim.tbl_contains({ 'O', 'L' }, response) do
    response = async.await(2, vim.ui.input, {
      prompt = 'Warning: The git index has changed and the buffer was changed as well. [O]K, (L)oad File:',
    })
  end
  return response == 'L'
end

--- @param name string
--- @return boolean
local function is_fugitive_diff_window(name)
  return vim.startswith(name, 'fugitive://')
    and vim.fn.exists('*FugitiveParse')
    and vim.fn.FugitiveParse(name)[1] ~= ':'
end

--- This function needs to be throttled as there is a call to vim.ui.input
--- @async
--- @param bufnr integer
--- @param _callback? fun()
M.update = throttle_by_id(function(bufnr, _callback)
  if not vim.wo.diff then
    return
  end

  -- Note this will be the bufname for the currently set base
  -- which are the only ones we want to update
  local bufname = assert(cache[bufnr]):get_rev_bufname()

  for _, w in ipairs(api.nvim_list_wins()) do
    if api.nvim_win_is_valid(w) then
      local b = api.nvim_win_get_buf(w)
      local bname = api.nvim_buf_get_name(b)
      if bname == bufname or is_fugitive_diff_window(bname) then
        if should_reload(b) then
          api.nvim_buf_call(b, function()
            vim.cmd.doautocmd('BufReadCmd')
            vim.cmd.diffthis()
          end)
        end
      end
    end
  end
end)

return M
