local Hunk = require("gitsigns.hunks").Hunk
local GitObj = require('gitsigns.git').Obj

local record M
  record CacheEntry
    file          : string
    base          : string
    compare_text  : {string}  -- For use with internal diff
    hunks         : {Hunk}
    force_next_update: boolean
    staged_diffs  : {Hunk}
    gitdir_watcher : vim.loop.FSPollObj -- Timer object watching the gitdir
    git_obj       : GitObj
    commit        : string

    get_compare_rev: function(CacheEntry, base: string): string
    get_rev_bufname: function(self: CacheEntry, rev: string): string
    invalidate: function(CacheEntry)
    new: function(CacheEntry): CacheEntry
    destroy: function(CacheEntry)
  end

  record CacheObj
   {CacheEntry}

   destroy: function(CacheObj, bufnr: integer)
  end

  cache: CacheObj
end

local CacheEntry = M.CacheEntry

CacheEntry.get_compare_rev = function(self: CacheEntry, base: string): string
  base = base or self.base
  if base then
    return base
  end

  if self.commit then
    -- Buffer is a fugutive commit so compare against the parent of the commit
    return string.format('%s^', self.commit)
  end

  local stage = self.git_obj.has_conflicts and 1 or 0
  return string.format(':%d', stage)
end

CacheEntry.get_rev_bufname = function(self: CacheEntry, rev: string): string
  rev = rev or self:get_compare_rev()
  return string.format(
    'gitsigns://%s/%s:%s',
    self.git_obj.repo.gitdir,
    rev,
    self.git_obj.relpath
  )
end

CacheEntry.invalidate = function(self: CacheEntry)
  self.compare_text = nil
  self.hunks = nil
end

CacheEntry.new = function(o: CacheEntry): CacheEntry
  o.hunks        = o.hunks
  o.staged_diffs = o.staged_diffs or {}
  return setmetatable(o, {__index = CacheEntry})
end

CacheEntry.destroy = function(self: CacheEntry)
  local w = self.gitdir_watcher
  if w then
    w:stop()
  end
end

M.CacheObj.destroy = function(self: M.CacheObj, bufnr: integer)
  self[bufnr]:destroy()
  self[bufnr] = nil
end

M.cache = setmetatable({}, {
  __index = M.CacheObj,
})

return M
