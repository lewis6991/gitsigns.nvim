local api = vim.api
local uv = vim.uv or vim.loop ---@diagnostic disable-line: deprecated

local async = require('gitsigns.async')
local log = require('gitsigns.debug.log')
local util = require('gitsigns.util')
local Status = require('gitsigns.status')

local cache = require('gitsigns.cache').cache
local config = require('gitsigns.config').config
local throttle_by_id = require('gitsigns.debounce').throttle_by_id
local debounce_trailing = require('gitsigns.debounce').debounce_trailing

local dprint = log.dprint
local dprintf = log.dprintf

--- @async
--- @param bufnr integer
--- @param old_relpath? string
local function handle_moved(bufnr, old_relpath)
  local bcache = assert(cache[bufnr])
  local git_obj = bcache.git_obj

  local orig_relpath = assert(git_obj.orig_relpath or old_relpath)
  git_obj.orig_relpath = orig_relpath
  local new_name = git_obj.repo:rename_status()[orig_relpath]
  if new_name then
    dprintf('File moved to %s', new_name)
    git_obj.relpath = new_name
    git_obj.file = git_obj.repo.toplevel .. '/' .. new_name
  elseif git_obj.orig_relpath then
    local orig_file = git_obj.repo.toplevel .. util.path_sep .. git_obj.orig_relpath
    if not git_obj.repo:file_info(orig_file, git_obj.revision) then
      return
    end
    --- File was moved in the index, but then reset
    dprintf('Moved file reset')
    git_obj.relpath = git_obj.orig_relpath
    git_obj.orig_relpath = nil
  else
    -- File removed from index, do nothing
    return
  end

  git_obj.file = git_obj.repo.toplevel .. util.path_sep .. git_obj.relpath
  bcache.file = git_obj.file
  git_obj:refresh()
  if not bcache:schedule() then
    return
  end

  local bufexists = util.bufexists(bcache.file)
  local old_name = api.nvim_buf_get_name(bufnr)

  if not bufexists then
    -- Do not trigger BufFilePre/Post
    -- TODO(lewis6991): figure out how to avoid reattaching without
    -- disabling all autocommands.
    util.noautocmd({ 'BufFilePre', 'BufFilePost' }, function()
      util.buf_rename(bufnr, bcache.file)
    end)
  end

  local msg = bufexists and 'Cannot rename' or 'Renamed'
  dprintf('%s buffer %d from %s to %s', msg, bufnr, old_name, bcache.file)
end

--- @async
--- @param bufnr integer
local function watcher_handler0(bufnr)
  local __FUNC__ = 'watcher_handler'

  local bcache = cache[bufnr]
  if not bcache then
    return
  end

  -- Avoid cache hit for detached buffer
  -- ref: https://github.com/lewis6991/gitsigns.nvim/issues/956
  if not bcache:schedule() then
    dprint('buffer invalid (1)')
    return
  end

  local git_obj = bcache.git_obj

  git_obj.repo:update_abbrev_head()

  if not bcache:schedule() then
    dprint('buffer invalid (2)')
    return
  end

  Status:update(bufnr, { head = git_obj.repo.abbrev_head })

  local was_tracked = git_obj.object_name ~= nil
  local old_relpath = git_obj.relpath

  bcache:invalidate(true)
  git_obj:refresh()
  if not bcache:schedule() then
    dprint('buffer invalid (3)')
    return
  end

  if config.watch_gitdir.follow_files and was_tracked and not git_obj.object_name then
    -- File was tracked but is no longer tracked. Must of been removed or
    -- moved. Check if it was moved and switch to it.
    handle_moved(bufnr, old_relpath)
    if not bcache:schedule() then
      dprint('buffer invalid (4)')
      return
    end
  end

  require('gitsigns.manager').update(bufnr)
end

--- Debounce to:
--- - wait for all changes to the gitdir to complete.
--- Throttle to:
--- - ensure handler is only triggered once per git operation.
--- - prevent updates to the same buffer from interleaving as the handler is
---   async.
local watcher_handler =
  debounce_trailing(200, async.create(1, throttle_by_id(watcher_handler0, true)), 1)

--- vim.inspect but on one line
--- @param x any
--- @return string
local function inspect(x)
  return vim.inspect(x, { indent = '', newline = ' ' })
end

local M = {}

--- @param bufnr integer
--- @param gitdir string
--- @return uv.uv_fs_event_t
function M.watch_gitdir(bufnr, gitdir)
  dprintf('Watching git dir')
  local w = assert(uv.new_fs_event())
  w:start(gitdir, {}, function(err, filename, events)
    local __FUNC__ = 'watcher_cb'
    if err then
      dprintf('Git dir update error: %s', err)
      return
    end

    -- The luv docs say filename is passed as a string but it has been observed
    -- to sometimes be nil.
    --    https://github.com/lewis6991/gitsigns.nvim/issues/848
    if not filename then
      log.eprint('No filename')
      return
    end

    dprintf("Git dir update: '%s' %s", filename, inspect(events))

    watcher_handler(bufnr)
  end)
  return w
end

return M
