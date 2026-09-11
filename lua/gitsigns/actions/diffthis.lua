local async = require('gitsigns.async')
local config = require('gitsigns.config').config
local manager = require('gitsigns.manager')
local message = require('gitsigns.message')
local util = require('gitsigns.util')
local Status = require('gitsigns.status')

local cache = require('gitsigns.cache').cache
local log = require('gitsigns.debug.log')
local throttle_async = require('gitsigns.debounce').throttle_async

local api = vim.api

local M = {}

--- @param bufnr integer
--- @param text string[]
local function read_revision(bufnr, text)
  -- Use Neovim's file reader to detect encoding, line endings, and the BOM.
  local path = vim.fn.tempname()
  local ok, err = pcall(function()
    vim.fn.writefile(text, path, 'b')
    api.nvim_buf_call(bufnr, function()
      api.nvim_buf_set_lines(bufnr, 0, -1, false, { '' })
      vim.cmd('silent noautocmd keepalt 0read ++edit ' .. vim.fn.fnameescape(path))

      -- :read leaves the empty buffer's original line after the inserted text.
      api.nvim_buf_set_lines(bufnr, -2, -1, false, {})
    end)
  end)

  vim.fn.delete(path)
  if not ok then
    error(err)
  end
end

--- @async
--- @param repo Gitsigns.Repo
--- @param dbufnr integer
--- @param base string?
--- @param relpath string
--- @param bufnr integer?
local function bufread(repo, dbufnr, base, relpath, bufnr)
  local bcache = bufnr and cache[bufnr]
  base = util.norm_base(base)

  -- Reuse the attached buffer's comparison text when it describes this revision.
  local text --- @type string[]
  if bcache and base == bcache.git_obj.revision and relpath == bcache.git_obj.relpath then
    text = assert(bcache.compare_text)
  else
    local err
    if bcache then
      text, err = bcache.git_obj:get_show_text(base, relpath)
    else
      text, err = repo:get_show_text(assert(base) .. ':' .. relpath)
    end
    if err then
      error(err, 2)
    end
    async.schedule()
    if not api.nvim_buf_is_valid(dbufnr) then
      return
    end
  end

  -- Match the source file's format before replacing text and restoring protection.
  local modifiable = vim.bo[dbufnr].modifiable
  vim.bo[dbufnr].modifiable = true
  vim.bo[dbufnr].fileformat = bcache
      and relpath == bcache.git_obj.relpath
      and vim.bo[assert(bufnr)].fileformat
    or (text[1] and text[1]:sub(-1) == '\r' and 'dos' or 'unix')

  vim.bo[dbufnr].filetype = vim.filetype.match({ buf = dbufnr })
  vim.bo[dbufnr].bufhidden = 'wipe'

  Status.update(dbufnr, { head = base })

  if bcache then
    util.set_lines(dbufnr, 0, -1, text)
  else
    read_revision(dbufnr, text)
  end

  vim.bo[dbufnr].modifiable = modifiable
  vim.bo[dbufnr].modified = false

  -- TODO(lewis6991): make this blocking
  require('gitsigns.attach').attach({
    bufnr = dbufnr,
    trigger = 'BufReadCmd',
    ctx = not bufnr
        and { file = relpath, base = base, gitdir = repo.gitdir, toplevel = repo.toplevel }
      or nil,
  })
end

--- @async
--- @param bufnr integer
--- @param dbufnr integer
--- @param base string?
local function bufwrite(bufnr, dbufnr, base)
  local bcache = assert(cache[bufnr])
  local buftext = util.buf_lines(dbufnr)
  base = util.norm_base(base)
  bcache.git_obj:lock(function()
    bcache.git_obj:stage_lines(buftext)
  end)
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
--- @param repo Gitsigns.Repo
--- @param base string?
--- @param relpath string
--- @param bufnr integer? Source buffer, required for editable index revisions.
--- @return string? bufname Buffer name
--- @return integer? bufnr Buffer number
--- @return boolean? created Whether a new buffer was created.
--- @return boolean? loaded Whether the buffer was already loaded.
function M.create_revision_buf(repo, base, relpath, bufnr)
  base = util.norm_base(base)

  local name_base = base or (bufnr and assert(cache[bufnr]).git_obj.revision) or ':0'
  local bufname = ('gitsigns://%s//%s:%s'):format(repo.gitdir, name_base, relpath)

  local exists = util.bufexists(bufname)
  local dbuf = exists and vim.fn.bufnr(bufname) or api.nvim_create_buf(false, true)
  local loaded = exists and api.nvim_buf_is_loaded(dbuf)

  -- Editable index buffers already have a BufReadCmd to reload them.
  if exists and (loaded or vim.bo[dbuf].buftype == 'acwrite') then
    return bufname, dbuf, false, loaded
  end

  if not exists then
    api.nvim_buf_set_name(dbuf, bufname)
  end

  -- An unloaded historical buffer needs its contents populated again.
  local ok, err = pcall(bufread, repo, dbuf, base, relpath, bufnr)
  if not ok then
    message.error(err --[[@as string]])
    async.schedule()

    -- A failed reload must not delete a buffer that already belonged to the user.
    if exists then
      vim.bo[dbuf].modifiable = false
    else
      api.nvim_buf_delete(dbuf, { force = true })
    end
    return
  end

  -- Index buffers write back to Git; historical revisions remain read-only.
  if not base then
    assert(bufnr, 'Index revisions need a source buffer')
    vim.bo[dbuf].buftype = 'acwrite'

    api.nvim_create_autocmd('BufReadCmd', {
      group = 'gitsigns',
      buffer = dbuf,
      callback = function()
        async.run(bufread, repo, dbuf, base, relpath, bufnr):raise_on_error()
      end,
    })

    api.nvim_create_autocmd('BufWriteCmd', {
      group = 'gitsigns',
      buffer = dbuf,
      callback = function()
        async.run(bufwrite, bufnr, dbuf, base):raise_on_error()
      end,
    })
  else
    vim.bo[dbuf].buftype = 'nowrite'
    vim.bo[dbuf].modifiable = false
  end

  return bufname, dbuf, not exists, loaded
end

--- @async
--- @param base string?
--- @param opts? Gitsigns.DiffthisOpts
local function diffthis_rev(base, opts)
  local bufnr = api.nvim_get_current_buf()
  local git_obj = assert(cache[bufnr]).git_obj

  local bufname, dbuf = M.create_revision_buf(git_obj.repo, base, assert(git_obj.relpath), bufnr)
  if not bufname then
    return
  end

  opts = opts or {}

  local cwin = api.nvim_get_current_win()

  vim.cmd.diffsplit({
    bufname,
    mods = {
      vertical = opts.vertical,
      split = opts.split or config.diffthis.split,
      keepalt = true,
    },
  })

  api.nvim_set_current_win(cwin)

  -- Reset 'diff' option for the current window if the diff buffer is hidden
  api.nvim_create_autocmd('BufHidden', {
    buffer = assert(dbuf),
    callback = function()
      if not api.nvim_win_is_valid(cwin) then
        return
      end
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

--- @async
--- @param base string?
--- @param opts Gitsigns.DiffthisOpts
function M.diffthis(base, opts)
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
end

--- @async
--- @param bufnr integer?
--- @param base string?
--- @param relpath string?
--- @return boolean did_attach
function M.show(bufnr, base, relpath)
  bufnr = bufnr or api.nvim_get_current_buf()

  if not cache[bufnr] then
    print('Error: Buffer is not attached.')
    return false
  end

  local git_obj = cache[bufnr].git_obj
  local bufname =
    M.create_revision_buf(git_obj.repo, base, relpath or assert(git_obj.relpath), bufnr)
  if not bufname then
    log.dprint('No bufname for revision ' .. base)
    return false
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
    return false
  end
  return true
end

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
    and vim.fn.exists('*FugitiveParse') == 1
    and vim.fn.FugitiveParse(name)[1] ~= ':'
end

--- This function needs to be throttled as there is a call to vim.ui.input
--- @param bufnr integer
M.update = throttle_async({ hash = 1, schedule = true }, function(bufnr)
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
            vim.cmd.diffupdate()
          end)
        end
      end
    end
  end
end)

return M
