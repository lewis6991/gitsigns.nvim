local Hunk = require("gitsigns.hunks").Hunk
local GitObj = require('gitsigns.git').Obj
local config = require('gitsigns.config').config

local record M
  record CacheEntry
    file          : string
    base          : string
    compare_text  : {string}
    hunks         : {Hunk}
    force_next_update: boolean

    compare_text_head : {string}
    hunks_staged      : {Hunk}

    staged_diffs  : {Hunk}
    gitdir_watcher : vim.loop.FSPollObj -- Timer object watching the gitdir
    git_obj       : GitObj
    commit        : string

    get_compare_rev        : function(CacheEntry, base: string): string
    get_staged_compare_rev : function(CacheEntry): string
    get_rev_bufname        : function(CacheEntry, rev: string): string
    invalidate             : function(CacheEntry)
    new                    : function(CacheEntry): CacheEntry
    destroy                : function(CacheEntry)
  end

  record CacheObj
   {CacheEntry}

   destroy: function(CacheObj, bufnr: integer)
  end

  cache: CacheObj
end

local CacheEntry = M.CacheEntry

function CacheEntry:get_compare_rev(base: string): string
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

function CacheEntry:get_staged_compare_rev(): string
  return self.commit and string.format('%s^', self.commit) or 'HEAD'
end

function CacheEntry:get_rev_bufname(rev: string): string
  rev = rev or self:get_compare_rev()
  return string.format(
    'gitsigns://%s/%s:%s',
    self.git_obj.repo.gitdir,
    rev,
    self.git_obj.relpath
  )
end

function CacheEntry:invalidate()
  self.compare_text = nil
  self.compare_text_head = nil
  self.hunks = nil
  self.hunks_staged = nil
end

function CacheEntry.new(o: CacheEntry): CacheEntry
  o.staged_diffs = o.staged_diffs or {}
  return setmetatable(o, {__index = CacheEntry})
end

function CacheEntry:destroy()
  local w = self.gitdir_watcher
  if w and not w:is_closing() then
    w:close()
  end
end

function M.CacheObj:destroy(bufnr: integer)
  self[bufnr]:destroy()
  self[bufnr] = nil
end

M.cache = setmetatable({}, {
  __index = M.CacheObj,
})

return M
