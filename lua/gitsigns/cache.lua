local Hunk = require("gitsigns.hunks").Hunk
local Sign = require('gitsigns.signs').Sign
local GitObj = require('gitsigns.git').Obj

local M = {CacheEntry = {}, CacheObj = {}, }


























local CacheEntry = M.CacheEntry

CacheEntry.get_compare_obj = function(self, base)
   base = base or self.base
   local prefix
   if base then
      prefix = base
   elseif self.commit then

      prefix = string.format('%s^', self.commit)
   else
      local stage = self.git_obj.has_conflicts and 1 or 0
      prefix = string.format(':%d', stage)
   end

   return string.format('%s:%s', prefix, self.git_obj.relpath)
end

CacheEntry.new = function(o)
   o.hunks = o.hunks or {}
   o.staged_diffs = o.staged_diffs or {}
   o.compare_file = o.compare_file or os.tmpname()
   return setmetatable(o, { __index = CacheEntry })
end

CacheEntry.destroy = function(self)
   os.remove(self.compare_file)
   local w = self.index_watcher
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
