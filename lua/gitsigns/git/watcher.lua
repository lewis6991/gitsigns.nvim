local uv = vim.loop

local async = require('gitsigns.async')
local log = require('gitsigns.debug.log')

local dprint = log.dprint
local dprintf = log.dprintf

-- vim.inspect but on one line
--- @param x any
--- @return string
local function inspect(x)
  return vim.inspect(x, { indent = '', newline = ' ' })
end

local M = {}

local WATCH_IGNORE = {
  ORIG_HEAD = true,
  FETCH_HEAD = true
}

--- @param repo Gitsigns.Repo
--- @return uv.uv_fs_event_t
function M.watch_gitdir(repo)
  dprintf('Watching git dir')
  local w = assert(uv.new_fs_event())
  w:start(repo.gitdir, {}, function(err, filename, events)
    local __FUNC__ = 'watcher_cb'
    if err then
      dprintf('Git dir update error: %s', err)
      return
    end

    local info = string.format("Git dir update for '%s': '%s' %s", repo.gitdir, filename, inspect(events))

    -- The luv docs say filename is passed as a string but it has been observed
    -- to sometimes be nil.
    --    https://github.com/lewis6991/gitsigns.nvim/issues/848
    if filename == nil or WATCH_IGNORE[filename] or vim.endswith(filename, '.lock') then
      dprintf('%s (ignoring)', info)
      return
    end

    dprint(info)

    async.run(function()
      repo:update()
      for _, cb in pairs(repo.callbacks) do
        cb()
      end
    end)
  end)
  return w
end

return M
