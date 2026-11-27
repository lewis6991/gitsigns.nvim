local async = require('gitsigns.async')
local config = require('gitsigns.config').config
local DiffBuffers = require('gitsigns.diff_buffers')
local manager = require('gitsigns.manager')
local message = require('gitsigns.message')
local util = require('gitsigns.util')
local Status = require('gitsigns.status')
local Unified = require('gitsigns.unified')

local cache = require('gitsigns.cache').cache
local log = require('gitsigns.debug.log')
local throttle_async = require('gitsigns.debounce').throttle_async

local api = vim.api

local M = {}
local pending_reads = {} --- @type table<string, Gitsigns.async.Event>

--- @class (exact) Gitsigns.RevisionFormat
--- @field buffer string Buffer 'fileformat' when the revision was read.
--- @field text 'unix'|'dos' Line endings removed for display and restored for writes.

--- Set the full revision text after it has been decoded to UTF-8.
--- @param bufnr integer
--- @param text string[]
--- @param encoding string
--- @param fileformat 'unix'|'dos' Line endings in the input text.
local function set_revision_text(bufnr, text, encoding, fileformat)
  vim.bo[bufnr].fileencoding = encoding

  local lines
  if fileformat == 'dos' then
    lines = util.strip_cr(text, text[#text] ~= '')
  else
    lines = vim.deepcopy(text)
  end

  local utf8_bom = '\239\187\191'
  local first_line = lines[1]
  if first_line and vim.startswith(first_line, utf8_bom) then
    vim.bo[bufnr].bomb = true
    lines[1] = first_line:sub(#utf8_bom + 1)
  else
    vim.bo[bufnr].bomb = false
  end

  if lines[#lines] == '' then
    lines[#lines] = nil
  else
    vim.bo[bufnr].eol = false
  end
  api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
end

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

--- Set revision text, using the source encoding when it is known.
--- @param bufnr integer
--- @param text string[]
--- @param bcache? Gitsigns.CacheEntry
--- @param relpath? string
--- @return 'unix'|'dos' text_format
local function populate_revision(bufnr, text, bcache, relpath)
  local bo = vim.bo[bufnr]
  local modifiable = bo.modifiable
  local same_file = bcache and relpath == bcache.git_obj.relpath
  bo.modifiable = true
  bo.fileformat = bcache and same_file and vim.bo[bcache.bufnr].fileformat
    or (text[1] and text[1]:sub(-1) == '\r' and 'dos' or 'unix')

  local text_format --- @type 'unix'|'dos'
  if bcache then
    -- Keep mixed endings and literal CR so editable index buffers can restore their bytes.
    local dos = bo.fileformat == 'dos'
      and util.is_dos(text)
      and (not same_file or bcache:compare_fileformat(text) == 'dos')
    text_format = dos and 'dos' or 'unix'
    set_revision_text(bufnr, text, bcache.git_obj.encoding, text_format)
  else
    read_revision(bufnr, text)
    text_format = bo.fileformat --[[@as 'unix'|'dos']]
  end

  bo.modifiable = modifiable
  bo.modified = false
  return text_format
end

--- @param name string
--- @return integer?
local function find_buffer(name)
  -- bufnr() can interpret a name as a pattern when there is no exact match.
  return util.bufexists(name) and vim.fn.bufnr(name) or nil
end

--- @async
--- @param repo Gitsigns.Repo
--- @param dbufnr integer
--- @param base string?
--- @param relpath string
--- @param bufnr integer?
local function bufread(repo, dbufnr, base, relpath, bufnr)
  local bcache = bufnr and cache[bufnr]
  local index = base == ':0'
  base = util.norm_base(base)

  -- Reuse the attached buffer's comparison text when it describes this revision.
  local text --- @type string[]
  if bcache and base == bcache.git_obj.revision and relpath == bcache.git_obj.relpath then
    text = assert(bcache.compare_text)
  else
    local err
    if index then
      text, err = repo:get_show_text(':0:' .. relpath, bcache and bcache.git_obj.encoding)
    elseif bcache then
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

  local text_format = populate_revision(dbufnr, text, bcache, relpath)
  vim.b[dbufnr].gitsigns_revision_format = {
    buffer = vim.bo[dbufnr].fileformat,
    text = text_format,
  }
  vim.bo[dbufnr].filetype = vim.filetype.match({ buf = dbufnr })
  Status.update(dbufnr, { head = base })

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
  -- The source can be a historical buffer that was wiped when the index opened.
  if
    not cache[bufnr]
    or (cache[dbufnr] and cache[bufnr].git_obj.relpath ~= cache[dbufnr].git_obj.relpath)
  then
    bufnr = dbufnr
  end
  local bcache = assert(cache[bufnr])
  local format = vim.b[dbufnr].gitsigns_revision_format --[[@as Gitsigns.RevisionFormat]]
  -- An explicit format change uses Git's normal conversion rules when written.
  local fileformat = format.buffer == vim.bo[dbufnr].fileformat and format.text or nil
  local contents = util.buf_lines(dbufnr, true, fileformat)
  base = util.norm_base(base)
  bcache.git_obj:lock(function()
    bcache.git_obj:stage_lines(contents, fileformat == nil)
    bcache.git_obj:refresh()
  end)
  async.schedule()
  if not api.nvim_buf_is_valid(bufnr) then
    return
  end
  vim.bo[dbufnr].modified = false
  -- If diff buffer base matches the git_obj revision then also update the
  -- signs.
  if base == bcache.git_obj.revision then
    -- Read the stored blob, since Git may have converted the written bytes.
    bcache:invalidate(true)
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
  base = base == ':0' and base or util.norm_base(base)

  local name_base = base or (bufnr and assert(cache[bufnr]).git_obj.revision) or ':0'
  local bufname = ('gitsigns://%s//%s:%s'):format(repo.gitdir, name_base, relpath)

  -- Neovim marks a new scratch buffer loaded before its Git read finishes.
  while pending_reads[bufname] do
    pending_reads[bufname]:wait()
  end

  -- Editable index buffers already have a BufReadCmd to reload them.
  local dbuf = find_buffer(bufname)
  local loaded = dbuf ~= nil and api.nvim_buf_is_loaded(dbuf)
  if dbuf and (loaded or vim.bo[dbuf].buftype == 'acwrite') then
    return bufname, dbuf, false, loaded
  end

  local created = not dbuf
  dbuf = dbuf or api.nvim_create_buf(false, true)
  local ready = async.event()
  pending_reads[bufname] = ready
  local ok, err = pcall(function()
    if created then
      -- Reloads must preserve retention by a panel or unified view.
      vim.bo[dbuf].bufhidden = 'wipe'
      api.nvim_buf_set_name(dbuf, bufname)
    end
    bufread(repo, dbuf, base, relpath, bufnr)
  end)
  if not ok then
    message.error(err --[[@as string]])
    async.schedule()
  end

  -- Let the first caller retain the finished buffer or discard its read.
  vim.schedule(function()
    pending_reads[bufname] = nil
    ready:set()
  end)

  if not ok then
    -- A failed reload must not delete a buffer that already belonged to the user.
    if api.nvim_buf_is_valid(dbuf) then
      if created then
        DiffBuffers.discard(dbuf, true)
      else
        vim.bo[dbuf].modifiable = false
      end
    end
    return
  end
  if not api.nvim_buf_is_loaded(dbuf) then
    return
  end

  -- Index buffers write back to Git; historical revisions remain read-only.
  if not util.norm_base(base) then
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

  return bufname, dbuf, created, false
end

--- Open an immutable index snapshot for the diff panel.
--- @async
--- @param repo Gitsigns.Repo
--- @param oid string
--- @param relpath string
--- @return integer? buf
--- @return boolean? created
--- @return boolean? loaded
function M.create_snapshot_buf(repo, oid, relpath)
  local name = ('gitsigns-blob://%s//%s:%s'):format(repo.gitdir, oid, relpath)
  local buf = find_buffer(name)
  if buf and api.nvim_buf_is_loaded(buf) then
    return buf, false, true
  end

  -- Read before publishing a buffer. Another panel may finish the same read first.
  local text, err = repo:get_show_text(oid)
  async.schedule()
  buf = find_buffer(name)
  if buf and api.nvim_buf_is_loaded(buf) then
    return buf, false, true
  end
  if err then
    message.error(err)
    return
  end

  local created = not buf
  buf = buf or api.nvim_create_buf(false, true)
  local ok, read_err = pcall(populate_revision, buf, text)
  if not api.nvim_buf_is_valid(buf) then
    return
  end

  local bo = vim.bo[buf]
  bo.modifiable = false
  if not ok then
    DiffBuffers.discard(buf, created)
    message.error(read_err --[[@as string]])
    return
  end

  bo.buftype = 'nowrite'
  if created then
    bo.bufhidden = 'wipe'
    api.nvim_buf_set_name(buf, name)
  end
  bo.filetype = vim.filetype.match({ buf = buf })
  Status.update(buf, { head = oid })
  return buf, created, false
end

--- @async
--- @param base string?
--- @param opts? Gitsigns.DiffthisOpts
local function diffthis_rev(base, opts)
  local bufnr = api.nvim_get_current_buf()
  local git_obj = assert(cache[bufnr]).git_obj

  local bufname, dbuf, created, loaded =
    M.create_revision_buf(git_obj.repo, base, assert(git_obj.relpath), bufnr)
  if not bufname then
    return
  end

  opts = opts or {}

  local cwin = api.nvim_get_current_win()

  if opts.unified then
    Unified.show(cwin, assert(dbuf), created, loaded)
    return
  end

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
  if Unified.get_view() then
    Unified.close(api.nvim_get_current_win())
    if opts.unified then
      return
    end
  end
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
    -- A unified view has two sides; preserve the three-way conflict view.
    opts.unified = false
    diffthis_rev(':2', opts)
    opts.split = 'belowright'
    diffthis_rev(':3', opts)
  else
    diffthis_rev(base, opts)
  end
end

--- @class (exact) Gitsigns.ShowFileOpts : Gitsigns.ShowOpts
--- @field bufnr? integer Source buffer. Defaults to the current buffer.
--- @field path? string File path relative to the repository root.

--- @async
--- @param ref string?
--- @param opts? Gitsigns.ShowFileOpts
--- @return boolean did_attach
function M.show(ref, opts)
  opts = opts or {}
  local bufnr = opts.bufnr or api.nvim_get_current_buf()

  if not cache[bufnr] then
    print('Error: Buffer is not attached.')
    return false
  end

  local git_obj = cache[bufnr].git_obj
  local bufname =
    M.create_revision_buf(git_obj.repo, ref, opts.path or assert(git_obj.relpath), bufnr)
  if not bufname then
    log.dprint('No bufname for revision ' .. tostring(ref))
    return false
  end

  log.dprint('bufname ' .. bufname)
  vim.cmd[opts.open or 'edit']({ bufname, mods = { keepalt = true } })

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
  if not vim.wo.diff and not Unified.is_active(bufnr) then
    return
  end
  -- Note this will be the bufname for the currently set base
  -- which are the only ones we want to update
  local bufname = assert(cache[bufnr]):get_rev_bufname()

  -- Unified views retain their comparison buffer without displaying it.
  for _, b in ipairs(api.nvim_list_bufs()) do
    if
      api.nvim_buf_is_loaded(b) and (#vim.fn.win_findbuf(b) > 0 or Unified.is_active(bufnr, b))
    then
      local bname = api.nvim_buf_get_name(b)
      if bname == bufname or is_fugitive_diff_window(bname) then
        if should_reload(b) then
          api.nvim_buf_call(b, function()
            vim.cmd.doautocmd('BufReadCmd')
            if vim.wo.diff then
              vim.cmd.diffupdate()
            end
          end)
        end
      end
    end
  end
end)

return M
