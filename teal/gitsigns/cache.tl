local Hunk = require("gitsigns.hunks").Hunk
local Sign = require('gitsigns.signs').Sign
local GitObj = require('gitsigns.git').Obj

local util = require('gitsigns.util')

local record M
  record CacheEntry
    file          : string
    index_watcher : vim.loop.FSPollObj -- Timer object watching the files index
    head_watcher  : vim.loop.FSPollObj -- Timer object watching the files HEAD
    git_obj       : GitObj

    commit        : string

    record Diff
      base          : string
      compare_file  : string    -- For use with externl diff
      compare_text  : {string}  -- For use with internal diff
      hunks         : {Hunk}
      pending_signs : {integer:Sign}
    end

    main: Diff
    sec:  Diff

    get_compare_obj: function(CacheEntry, base: string, sec: boolean): string
    get_compare_text: function(self: CacheEntry, sec: boolean): {string}
    staged_signs_enabled: function(CacheEntry, config_staged_signs: boolean): boolean

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

CacheEntry.get_compare_obj = function(self: CacheEntry, base: string, sec: boolean): string
  if sec then
    base = base or self.sec.base
  else
    base = base or self.main.base
  end
  local prefix: string
  if base then
    prefix = base
  elseif sec then
    prefix = 'HEAD'
  elseif self.commit then
    -- Buffer is a fugutive commit so compare against the parent of the commit
    prefix = string.format('%s^', self.commit)
  else
    local stage = self.git_obj.has_conflicts and 1 or 0
    prefix = string.format(':%d', stage)
  end

  return string.format('%s:%s', prefix, self.git_obj.relpath)
end

CacheEntry.get_compare_text = function(self: CacheEntry, sec: boolean): {string}
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

CacheEntry.staged_signs_enabled = function(self: CacheEntry, config_staged_signs: boolean): boolean
  return config_staged_signs and self.main.base == nil or self.sec.base ~= nil
end

CacheEntry.new = function(o: CacheEntry): CacheEntry
  o.main              = o.main              or {}
  o.main.hunks        = o.main.hunks        or {}
  o.main.compare_file = o.main.compare_file or os.tmpname()

  o.sec                = o.sec              or {}
  o.sec.hunks          = o.sec.hunks        or {}
  o.sec.compare_file   = o.sec.compare_file or os.tmpname()

  return setmetatable(o, {__index = CacheEntry})
end

CacheEntry.destroy = function(self: CacheEntry)
  os.remove(self.main.compare_file)
  os.remove(self.sec.compare_file)
  self.head_watcher:stop()
  self.index_watcher:stop()
end

M.CacheObj.destroy = function(self: M.CacheObj, bufnr: integer)
  self[bufnr]:destroy()
  self[bufnr] = nil
end

M.cache = setmetatable({}, {
  __index = M.CacheObj,
})

return M
