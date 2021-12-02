local Hunk = require("gitsigns.hunks").Hunk
local Sign = require('gitsigns.signs').Sign
local GitObj = require('gitsigns.git').Obj

local util = require('gitsigns.util')

local record M
  record CacheEntry
    file          : string
    base          : string
    compare_file  : string    -- For use with externl diff
    compare_text  : {string}  -- For use with internal diff
    hunks         : {Hunk}
    staged_diffs  : {Hunk}
    pending_signs : {integer:Sign}
    gitdir_watcher : vim.loop.FSPollObj -- Timer object watching the gitdir
    git_obj       : GitObj
    commit        : string

    get_compare_rev: function(CacheEntry, base: string): string
    get_compare_text: function(self: CacheEntry): {string}
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

CacheEntry.get_compare_text = function(self: CacheEntry): {string}
  if self.compare_text then
    return self.compare_text
  end
  return util.file_lines(self.compare_file)
end

CacheEntry.new = function(o: CacheEntry): CacheEntry
  o.hunks        = o.hunks
  o.staged_diffs = o.staged_diffs or {}
  o.compare_file = o.compare_file or util.tmpname()
  return setmetatable(o, {__index = CacheEntry})
end

CacheEntry.destroy = function(self: CacheEntry)
  os.remove(self.compare_file)
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
