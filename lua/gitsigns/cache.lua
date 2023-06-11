local config = require('gitsigns.config').config

local M = {
  CacheEntry = {},
  ---@class Gitsigns.CacheObj
  ---@field [integer] Gitsigns.CacheEntry
  ---@field destroy fun(self: Gitsigns.CacheObj, bufnr: integer)
  CacheObj = {}
}

-- Timer object watching the gitdir

--- @class Gitsigns.CacheEntry
--- @field compare_text?      string[]
--- @field compare_text_head? string[]
--- @field hunks              Gitsigns.Hunk.Hunk[]
--- @field hunks_staged?      Gitsigns.Hunk.Hunk[]
--- @field commit?            string
--- @field base?              string
--- @field git_obj           Gitsigns.GitObj
--- @field gitdir_watcher?    uv_poll_t
local CacheEntry = M.CacheEntry

function CacheEntry:get_compare_rev(base)
  base = base or self.base
  if base then
    return base
  end

  if self.commit then
    -- Buffer is a fugitive commit so compare against the parent of the commit
    if config._signs_staged_enable then
      return self.commit
    else
      return string.format('%s^', self.commit)
    end
  end

  local stage = self.git_obj.has_conflicts and 1 or 0
  return string.format(':%d', stage)
end

function CacheEntry:get_staged_compare_rev()
  return self.commit and string.format('%s^', self.commit) or 'HEAD'
end

function CacheEntry:get_rev_bufname(rev)
  rev = rev or self:get_compare_rev()
  return string.format('gitsigns://%s/%s:%s', self.git_obj.repo.gitdir, rev, self.git_obj.relpath)
end

function CacheEntry:invalidate()
  self.compare_text = nil
  self.compare_text_head = nil
  self.hunks = nil
  self.hunks_staged = nil
end

function CacheEntry.new(o)
  o.staged_diffs = o.staged_diffs or {}
  return setmetatable(o, { __index = CacheEntry })
end

function CacheEntry:destroy()
  local w = self.gitdir_watcher
  if w and not w:is_closing() then
    w:close()
  end
end

function M.CacheObj:destroy(bufnr)
  self[bufnr]:destroy()
  self[bufnr] = nil
end

M.cache = setmetatable({}, {
  __index = M.CacheObj,
})

return M
