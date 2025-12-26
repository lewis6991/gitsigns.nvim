local async = require('gitsigns.async')
local config = require('gitsigns.config').config
local log = require('gitsigns.debug.log')
local util = require('gitsigns.util')

local api = vim.api

local M = {
  CacheEntry = {},
}

--- @class (exact) Gitsigns.CacheEntry.Blame
--- @field entries table<integer,Gitsigns.BlameInfo?>
--- @field max_time? integer
--- @field min_time? integer

--- @class (exact) Gitsigns.CacheEntry
--- @field bufnr              integer
--- @field file               string
--- @field compare_text?      string[]
--- @field hunks?             Gitsigns.Hunk.Hunk[]
--- @field force_next_update? boolean
---
--- An update is required for the buffer next time it comes into view
--- @field update_on_view?    boolean
---
--- @field file_mode?         boolean
---
--- @field compare_text_head? string[]
--- @field hunks_staged?      Gitsigns.Hunk.Hunk[]
---
--- @field staged_diffs       Gitsigns.Hunk.Hunk[]
--- @field deregister_watcher? fun()
--- @field git_obj            Gitsigns.GitObj
--- @field blame?             Gitsigns.CacheEntry.Blame
--- @field commits?           table<string,Gitsigns.CommitInfo?>
local CacheEntry = M.CacheEntry

--- @param rev? string
--- @param filename? false|string
--- @return string
function CacheEntry:get_rev_bufname(rev, filename)
  rev = rev or self.git_obj.revision or ':0'
  local gitdir = self.git_obj.repo.gitdir
  if filename == false then
    return ('gitsigns://%s//%s'):format(gitdir, rev)
  end
  return ('gitsigns://%s//%s:%s'):format(gitdir, rev, filename or self.git_obj.relpath)
end

--- Invalidate any state dependent on the buffer content.
--- If 'all' is passed, then invalidate everything.
--- @param all? boolean
function CacheEntry:invalidate(all)
  self.hunks = nil
  self.hunks_staged = nil
  self.blame = nil
  self.commits = nil
  if all then
    -- The below doesn't need to be invalidated
    -- if the buffer changes
    self.compare_text = nil
    self.compare_text_head = nil
  end
end

--- @param bufnr integer
--- @param file string
--- @param git_obj Gitsigns.GitObj
--- @return Gitsigns.CacheEntry
function M.new(bufnr, file, git_obj)
  return setmetatable({
    bufnr = bufnr,
    file = file,
    git_obj = git_obj,
    staged_diffs = {},
  }, { __index = CacheEntry })
end

local sleep = async.wrap(2, function(duration, cb)
  vim.defer_fn(cb, duration)
end)

--- @async
--- @private
function CacheEntry:wait_for_hunks()
  local loop_protect = 0
  while not self.hunks and loop_protect < 10 do
    loop_protect = loop_protect + 1
    sleep(100)
  end
end

-- If a file contains has up to this amount of lines, then
-- always blame the whole file, otherwise only blame one line
-- at a time.
local BLAME_THRESHOLD_LEN = 10000

--- @async
--- @private
--- @param lnum? integer|[integer, integer]
--- @param opts? Gitsigns.BlameOpts
--- @return table<integer,Gitsigns.BlameInfo?>
--- @return table<string,Gitsigns.CommitInfo?>
--- @return boolean? full
function CacheEntry:run_blame(lnum, opts)
  local bufnr = self.bufnr

  -- Always send contents if buffer represents an editable file on disk.
  -- Otherwise do not sent contents buffer revision is from tree and git version
  -- is below 2.41.
  --
  -- This avoids the error:
  --   "fatal: cannot use --contents with final commit object name"
  local send_contents = vim.bo[bufnr].buftype == ''
    or (not self.git_obj:from_tree() and not require('gitsigns.git.version').check(2, 41))

  while true do
    local contents = send_contents and util.buf_lines(bufnr) or nil
    local tick = vim.b[bufnr].changedtick
    local lnum0 = api.nvim_buf_line_count(bufnr) > BLAME_THRESHOLD_LEN and lnum or nil
    -- TODO(lewis6991): Cancel blame on changedtick
    local blame, commits = self.git_obj:run_blame(contents, lnum0, self.git_obj.revision, opts)
    async.schedule()
    if not api.nvim_buf_is_valid(bufnr) then
      return {}, {}
    end
    if vim.b[bufnr].changedtick == tick then
      return blame, commits, lnum0 == nil
    end
  end
  error('unreachable')
end

--- @private
--- @param lnum? integer
--- @return boolean
function CacheEntry:blame_valid(lnum)
  local blame = self.blame
  if not blame then
    return false
  end

  if lnum then
    return blame.entries[lnum] ~= nil
  end

  -- Need to check we have blame info for all lines
  for i = 1, api.nvim_buf_line_count(self.bufnr) do
    if not blame.entries[i] then
      return false
    end
  end

  return true
end

--- If lnum is nil then run blame for the entire buffer.
--- @async
--- @param lnum? integer|[integer, integer]
--- @param opts? Gitsigns.BlameOpts
--- @return Gitsigns.BlameInfo?
function CacheEntry:get_blame(lnum, opts)
  local blame = self.blame

  local blame_valid = true
  if type(lnum) == 'table' then
    local curr_lnum = lnum[1]
    while blame_valid and curr_lnum <= lnum[2] do
      blame_valid = self:blame_valid(curr_lnum)
      curr_lnum = curr_lnum + 1
    end
  else
    blame_valid = self:blame_valid(lnum)
  end
  if not blame or not blame_valid then
    self:wait_for_hunks()
    blame = blame or { entries = {} }
    local Hunks = require('gitsigns.hunks')
    local has_blameable_line = true
    if lnum then
      local start_lnum = type(lnum) == 'table' and lnum[1] or lnum
      local end_lnum = type(lnum) == 'table' and lnum[2] or lnum
      for curr_lnum = start_lnum, end_lnum do
        has_blameable_line = not Hunks.find_hunk(curr_lnum, self.hunks)
        if has_blameable_line then
          break
        end
      end
    end
    if lnum and not has_blameable_line then
      --- Bypass running blame (which can be expensive) if we know lnum is in a hunk
      local Blame = require('gitsigns.git.blame')
      local relpath = assert(self.git_obj.relpath)
      local start_lnum = type(lnum) == 'table' and lnum[1] or lnum
      local end_lnum = type(lnum) == 'table' and lnum[2] or lnum
      for curr_lnum = start_lnum, end_lnum do
        local info = Blame.get_blame_nc(relpath, curr_lnum)
        blame.entries[curr_lnum] = info
        blame.max_time = info.commit.author_time
      end
    else
      -- Refresh/update cache
      local b, commits, full = self:run_blame(lnum, opts)
      self.commits = vim.tbl_extend('force', self.commits or {}, commits)
      if lnum and not full then
        local start_lnum = type(lnum) == 'table' and lnum[1] or lnum
        local end_lnum = type(lnum) == 'table' and lnum[2] or lnum
        for curr_lnum = start_lnum, end_lnum do
          blame.entries[curr_lnum] = b[curr_lnum]
        end
      else
        blame.entries = b
      end
    end
    self.blame = blame
  end

  return blame.entries[lnum]
end

--- @async
--- @nodiscard
--- @param check_compare_text? boolean
--- @return boolean
function CacheEntry:schedule(check_compare_text)
  async.schedule()
  local bufnr = self.bufnr
  if not api.nvim_buf_is_valid(bufnr) then
    log.dprint('Buffer not valid, aborting')
    return false
  end

  if not M.cache[bufnr] then
    log.dprint('Has detached, aborting')
    return false
  end

  if check_compare_text and not M.cache[bufnr].compare_text then
    log.dprint('compare_text was invalid, aborting')
    return false
  end

  return true
end

--- @async
--- @param greedy? boolean
--- @param staged? boolean
--- @return Gitsigns.Hunk.Hunk[]?
function CacheEntry:get_hunks(greedy, staged)
  if greedy and config.diff_opts.linematch then
    -- Re-run the diff without linematch
    local buftext = util.buf_lines(self.bufnr)
    local text --- @type string[]?
    if staged then
      text = self.compare_text_head
    else
      text = self.compare_text
    end
    if not text then
      return
    end
    local run_diff = require('gitsigns.diff')
    local hunks = run_diff(text, buftext, false)
    if not self:schedule() then
      return
    end
    return hunks
  end

  if staged then
    return self.hunks_staged and vim.deepcopy(self.hunks_staged) or nil
  end

  return self.hunks and vim.deepcopy(self.hunks) or nil
end

--- @param hunks? Gitsigns.Hunk.Hunk[]?
--- @return Gitsigns.Hunk.Hunk? hunk
--- @return integer? index
function CacheEntry:get_cursor_hunk(hunks)
  if not hunks then
    hunks = {}
    vim.list_extend(hunks, self.hunks or {})
    vim.list_extend(hunks, self.hunks_staged or {})
  end

  local lnum = api.nvim_win_get_cursor(0)[1]
  local Hunks = require('gitsigns.hunks')
  return Hunks.find_hunk(lnum, hunks)
end

--- @async
--- @param range? [integer,integer]
--- @param greedy? boolean
--- @param staged? boolean
--- @return Gitsigns.Hunk.Hunk?
function CacheEntry:get_hunk(range, greedy, staged)
  local Hunks = require('gitsigns.hunks')

  local hunks = self:get_hunks(greedy, staged)

  if not range then
    return (self:get_cursor_hunk(hunks))
  end

  table.sort(range)
  local top, bot = range[1], range[2]
  local hunk = Hunks.create_partial_hunk(hunks or {}, top, bot)
  if not hunk then
    return
  end

  local compare_text = assert(self.compare_text)

  if staged then
    local staged_top, staged_bot = top, bot
    for _, h in ipairs(assert(self.hunks)) do
      if top > h.vend then
        staged_top = staged_top - (h.added.count - h.removed.count)
      end
      if bot > h.vend then
        staged_bot = staged_bot - (h.added.count - h.removed.count)
      end
    end

    hunk.added.lines = vim.list_slice(compare_text, staged_top, staged_bot)
    hunk.removed.lines = vim.list_slice(
      assert(self.compare_text_head),
      hunk.removed.start,
      hunk.removed.start + hunk.removed.count - 1
    )
  else
    hunk.added.lines = api.nvim_buf_get_lines(self.bufnr, top - 1, bot, false)
    hunk.removed.lines =
      vim.list_slice(compare_text, hunk.removed.start, hunk.removed.start + hunk.removed.count - 1)
  end
  return hunk
end

function CacheEntry:get_blame_times()
  local blame = assert(self.blame)

  if blame.max_time and blame.min_time then
    return blame.min_time, blame.max_time
  end

  local min_time = math.huge --[[@as integer]]
  for _, c in pairs(assert(self.commits)) do
    min_time = math.min(min_time, c.author_time)
  end

  blame.min_time = min_time

  -- If the buffer can be edited, then always set the max time to now.
  -- For read-only buffers, set the max time to the latest commit time.
  if vim.bo[self.bufnr].modifiable then
    blame.max_time = os.time()
  else
    local max_time = 0 --[[@as integer]]
    for _, c in pairs(assert(self.commits)) do
      max_time = math.max(max_time, c.author_time)
    end
    blame.max_time = max_time
  end

  return blame.min_time, blame.max_time
end

function CacheEntry:destroy()
  if self.deregister_watcher then
    self.deregister_watcher()
    self.deregister_watcher = nil
  end
end

---@type table<integer,Gitsigns.CacheEntry?>
M.cache = {}

--- @param bufnr integer
function M.destroy(bufnr)
  assert(M.cache[bufnr]):destroy()
  M.cache[bufnr] = nil
end

return M
