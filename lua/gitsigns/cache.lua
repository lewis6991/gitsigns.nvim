local config = require('gitsigns.config').config

local M = {
  CacheEntry = {},
}

-- Timer object watching the gitdir

--- @class Gitsigns.CacheEntry
--- @field file               string
--- @field base?              string
--- @field compare_text?      string[]
--- @field hunks              Gitsigns.Hunk.Hunk[]
--- @field force_next_update? boolean
---
--- @field compare_text_head? string[]
--- @field hunks_staged?      Gitsigns.Hunk.Hunk[]
---
--- @field staged_diffs       Gitsigns.Hunk.Hunk[]
--- @field gitdir_watcher?    uv_fs_event_t
--- @field git_obj            Gitsigns.GitObj
--- @field commit?            string
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

--- @param o Gitsigns.CacheEntry
--- @return Gitsigns.CacheEntry
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

---@type table<integer,Gitsigns.CacheEntry>
M.cache = {}

--- @param bufnr integer
function M.destroy(bufnr)
  M.cache[bufnr]:destroy()
  M.cache[bufnr] = nil
end

return M
