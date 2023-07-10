local api = vim.api
local uv = vim.loop

local Status = require('gitsigns.status')
local async = require('gitsigns.async')
local log = require('gitsigns.debug.log')
local util = require('gitsigns.util')

local cache = require('gitsigns.cache').cache
local config = require('gitsigns.config').config
local debounce_trailing = require('gitsigns.debounce').debounce_trailing

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
  async.scheduler()

  local bufexists = util.bufexists(bcache.file)
  local old_name = api.nvim_buf_get_name(bufnr)

  if not bufexists then
    util.buf_rename(bufnr, bcache.file)
  end

  local msg = bufexists and 'Cannot rename' or 'Renamed'
  dprintf('%s buffer %d from %s to %s', msg, bufnr, old_name, bcache.file)
end

local watch_gitdir_handler = async.void(function(bufnr)
  if not cache[bufnr] then
    -- Very occasionally an external git operation may cause the buffer to
    -- detach and update the git dir simultaneously. When this happens this
    -- handler will trigger but there will be no cache.
    dprint('Has detached, aborting')
    return
  end

  local git_obj = cache[bufnr].git_obj

  git_obj.repo:update_abbrev_head()

  async.scheduler()
  Status:update(bufnr, { head = git_obj.repo.abbrev_head })

  local was_tracked = git_obj.object_name ~= nil
  local old_relpath = git_obj.relpath

  git_obj:update_file_info()

  if config.watch_gitdir.follow_files and was_tracked and not git_obj.object_name then
    -- File was tracked but is no longer tracked. Must of been removed or
    -- moved. Check if it was moved and switch to it.
    handle_moved(bufnr, old_relpath)
  end

  cache[bufnr]:invalidate()

  require('gitsigns.manager').update(bufnr, cache[bufnr])
end)

-- vim.inspect but on one line
--- @param x any
--- @return string
local function inspect(x)
  return vim.inspect(x, { indent = '', newline = ' ' })
end

local M = {}

--- @param bufnr integer
--- @param gitdir string
--- @return uv_fs_event_t?
function M.watch_gitdir(bufnr, gitdir)
  -- Setup debounce as we create the luv object so the debounce is independent
  -- to each watcher
  local watch_gitdir_handler_db = debounce_trailing(200, watch_gitdir_handler)

  dprintf('Watching git dir')
  local w = assert(uv.new_fs_event())
  w:start(gitdir, {}, function(err, filename, events)
    local __FUNC__ = 'watcher_cb'
    if err then
      dprintf('Git dir update error: %s', err)
      return
    end

    local info = string.format("Git dir update: '%s' %s", filename, inspect(events))

    if vim.endswith(filename, '.lock') then
      dprintf('%s (ignoring)', info)
      return
    end

    dprint(info)

    watch_gitdir_handler_db(bufnr)
  end)
  return w
end

return M
