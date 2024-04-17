local api = vim.api
local uv = vim.loop

local Status = require('gitsigns.status')
local async = require('gitsigns.async')
local log = require('gitsigns.debug.log')
local util = require('gitsigns.util')

local cache = require('gitsigns.cache').cache
local config = require('gitsigns.config').config
local debounce_trailing = require('gitsigns.debounce').debounce_trailing
local manager = require('gitsigns.manager')

local dprint = log.dprint
local dprintf = log.dprintf

--- @param bufnr integer
--- @param old_relpath string
local function handle_moved(bufnr, old_relpath)
  local bcache = cache[bufnr]
  local git_obj = bcache.git_obj

  local new_name = git_obj:has_moved()
  if new_name then
    dprintf('File moved to %s', new_name)
    git_obj.relpath = new_name
    if not git_obj.orig_relpath then
      git_obj.orig_relpath = old_relpath
    end
  elseif git_obj.orig_relpath then
    local orig_file = git_obj.repo.toplevel .. util.path_sep .. git_obj.orig_relpath
    if not git_obj:file_info(orig_file).relpath then
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
  git_obj:update_file_info()
  if not manager.schedule(bufnr) then
    return
  end

  local bufexists = util.bufexists(bcache.file)
  local old_name = api.nvim_buf_get_name(bufnr)

  if not bufexists then
    util.buf_rename(bufnr, bcache.file)
  end

  local msg = bufexists and 'Cannot rename' or 'Renamed'
  dprintf('%s buffer %d from %s to %s', msg, bufnr, old_name, bcache.file)
end

--- @param bufnr integer
local watcher_handler = async.create(1, function(bufnr)
  local __FUNC__ = 'watcher_handler'

  -- Avoid cache hit for detached buffer
  -- ref: https://github.com/lewis6991/gitsigns.nvim/issues/956
  if not manager.schedule(bufnr) then
    return
  end

  local git_obj = cache[bufnr].git_obj

  git_obj.repo:update_abbrev_head()

  if not manager.schedule(bufnr) then
    return
  end

  Status:update(bufnr, { head = git_obj.repo.abbrev_head })

  local was_tracked = git_obj.object_name ~= nil
  local old_relpath = git_obj.relpath

  git_obj:update_file_info()
  if not manager.schedule(bufnr) then
    return
  end

  if config.watch_gitdir.follow_files and was_tracked and not git_obj.object_name then
    -- File was tracked but is no longer tracked. Must of been removed or
    -- moved. Check if it was moved and switch to it.
    handle_moved(bufnr, old_relpath)
    if not manager.schedule(bufnr) then
      return
    end
  end

  cache[bufnr]:invalidate(true)

  require('gitsigns.manager').update(bufnr)
end)

local watcher_handler_debounced = debounce_trailing(200, watcher_handler, 1)

--- vim.inspect but on one line
--- @param x any
--- @return string
local function inspect(x)
  return vim.inspect(x, { indent = '', newline = ' ' })
end

local M = {}

local WATCH_IGNORE = {
  ORIG_HEAD = true,
  FETCH_HEAD = true,
}

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

    local info = string.format("Git dir update: '%s' %s", filename, inspect(events))

    -- The luv docs say filename is passed as a string but it has been observed
    -- to sometimes be nil.
    --    https://github.com/lewis6991/gitsigns.nvim/issues/848
    if filename == nil or WATCH_IGNORE[filename] or vim.endswith(filename, '.lock') then
      dprintf('%s (ignoring)', info)
      return
    end

    dprint(info)

    watcher_handler_debounced(bufnr)
  end)
  return w
end

return M
