local Hunk = require("gitsigns.hunks").Hunk
local GitObj = require('gitsigns.git').Obj

local M = {CacheEntry = {}, CacheObj = {}, }



























local CacheEntry = M.CacheEntry

CacheEntry.get_compare_rev = function(self, base)
   base = base or self.base
   if base then
      return base
   end

   if self.commit then

      return string.format('%s^', self.commit)
   end

   local stage = self.git_obj.has_conflicts and 1 or 0
   return string.format(':%d', stage)
end

CacheEntry.get_rev_bufname = function(self, rev)
   rev = rev or self:get_compare_rev()
   return string.format(
   'gitsigns://%s/%s:%s',
   self.git_obj.repo.gitdir,
   rev,
   self.git_obj.relpath)

end

CacheEntry.invalidate = function(self)
   self.compare_text = nil
   self.hunks = nil
end

CacheEntry.new = function(o)
   o.hunks = o.hunks
   o.staged_diffs = o.staged_diffs or {}
   return setmetatable(o, { __index = CacheEntry })
end

CacheEntry.destroy = function(self)
   local w = self.gitdir_watcher
   if w then
      w:stop()
   end
end

M.CacheObj.destroy = function(self, bufnr)
   self[bufnr]:destroy()
   self[bufnr] = nil
end

M.cache = setmetatable({}, {
   __index = M.CacheObj,
})

return M
