local Hunk = require("gitsigns.hunks").Hunk
local Sign = require('gitsigns.signs').Sign
local GitObj = require('gitsigns.git').Obj

local util = require('gitsigns.util')

local M = {CacheEntry = {Diff = {}, }, CacheObj = {}, }




































local CacheEntry = M.CacheEntry

CacheEntry.get_compare_obj = function(self, base, sec)
   if sec then
      base = base or self.sec.base
   else
      base = base or self.main.base
   end
   local prefix
   if base then
      prefix = base
   elseif sec then
      prefix = 'HEAD'
   elseif self.commit then

      prefix = string.format('%s^', self.commit)
   else
      local stage = self.git_obj.has_conflicts and 1 or 0
      prefix = string.format(':%d', stage)
   end

   return string.format('%s:%s', prefix, self.git_obj.relpath)
end

CacheEntry.get_compare_text = function(self, sec)
   if sec then
      if self.sec.compare_text then
         return self.sec.compare_text
      end
      return util.file_lines(self.sec.compare_file)
   else
      if self.main.compare_text then
         return self.main.compare_text
      end
      return util.file_lines(self.main.compare_file)
   end
end

CacheEntry.staged_signs_enabled = function(self, config_staged_signs)
   return config_staged_signs and self.main.base == nil or self.sec.base ~= nil
end

CacheEntry.new = function(o)
   o.main = o.main or {}
   o.main.hunks = o.main.hunks or {}
   o.main.compare_file = o.main.compare_file or os.tmpname()

   o.sec = o.sec or {}
   o.sec.hunks = o.sec.hunks or {}
   o.sec.compare_file = o.sec.compare_file or os.tmpname()

   return setmetatable(o, { __index = CacheEntry })
end

CacheEntry.destroy = function(self)
   os.remove(self.main.compare_file)
   os.remove(self.sec.compare_file)
   self.head_watcher:stop()
   self.index_watcher:stop()
end

M.CacheObj.destroy = function(self, bufnr)
   self[bufnr]:destroy()
   self[bufnr] = nil
end

M.cache = setmetatable({}, {
   __index = M.CacheObj,
})

return M
