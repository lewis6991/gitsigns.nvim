local async = require('gitsigns.async')
local config = require('gitsigns.config').config
local log = require('gitsigns.debug.log')
local util = require('gitsigns.util')

local api = vim.api

local M = {
  CacheEntry = {},
}

--- @class (exact) Gitsigns.CacheEntry
--- @field bufnr              integer
--- @field file               string
--- @field compare_text?      string[]
--- @field hunks?             Gitsigns.Hunk.Hunk[]
--- @field force_next_update? boolean
--- @field file_mode?         boolean
---
--- @field compare_text_head? string[]
--- @field hunks_staged?      Gitsigns.Hunk.Hunk[]
---
--- @field staged_diffs       Gitsigns.Hunk.Hunk[]
--- @field gitdir_watcher?    uv.uv_fs_event_t
--- @field git_obj            Gitsigns.GitObj
--- @field blame?             table<integer,Gitsigns.BlameInfo?>
---
--- @field update_lock?       true Update in progress
local CacheEntry = M.CacheEntry

function CacheEntry:get_rev_bufname(rev, nofile)
  rev = rev or self.git_obj.revision or ':0'
  if nofile then
    return string.format('gitsigns://%s//%s', self.git_obj.repo.gitdir, rev)
  end
  return string.format('gitsigns://%s//%s:%s', self.git_obj.repo.gitdir, rev, self.git_obj.relpath)
end

function CacheEntry:locked()
  return self.git_obj.lock or self.update_lock or false
end

--- Invalidate any state dependent on the buffer content.
--- If 'all' is passed, then invalidate everything.
--- @param all? boolean
function CacheEntry:invalidate(all)
  self.hunks = nil
  self.hunks_staged = nil
  self.blame = nil
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

local sleep = async.awrap(2, function(duration, cb)
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
--- @param lnum? integer
--- @param opts? Gitsigns.BlameOpts
--- @return table<integer,Gitsigns.BlameInfo?>
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
    local blame = self.git_obj:run_blame(contents, lnum0, self.git_obj.revision, opts)
    async.schedule()
    if not api.nvim_buf_is_valid(bufnr) then
      return {}
    end
    if vim.b[bufnr].changedtick == tick then
      return blame, lnum0 == nil
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
    return blame[lnum] ~= nil
  end

  -- Need to check we have blame info for all lines
  for i = 1, api.nvim_buf_line_count(self.bufnr) do
    if not blame[i] then
      return false
    end
  end

  return true
end

--- If lnum is nil then run blame for the entire buffer.
--- @async
--- @param lnum? integer
--- @param opts? Gitsigns.BlameOpts
--- @return Gitsigns.BlameInfo?
function CacheEntry:get_blame(lnum, opts)
  local blame = self.blame

  if not blame or not self:blame_valid(lnum) then
    self:wait_for_hunks()
    blame = blame or {}
    local Hunks = require('gitsigns.hunks')
    if lnum and Hunks.find_hunk(lnum, self.hunks) then
      --- Bypass running blame (which can be expensive) if we know lnum is in a hunk
      local Blame = require('gitsigns.git.blame')
      local relpath = assert(self.git_obj.relpath)
      blame[lnum] = Blame.get_blame_nc(relpath, lnum)
    else
      -- Refresh/update cache
      local b, full = self:run_blame(lnum, opts)
      if lnum and not full then
        blame[lnum] = b[lnum]
      else
        blame = b
      end
    end
    self.blame = blame
  end

  return blame[lnum]
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
    return vim.deepcopy(self.hunks_staged)
  end

  return vim.deepcopy(self.hunks)
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

function CacheEntry:destroy()
  local w = self.gitdir_watcher
  if w and not w:is_closing() then
    w:close()
  end
  self.git_obj.repo:unref()
end

---@type table<integer,Gitsigns.CacheEntry?>
M.cache = {}

--- @param bufnr integer
function M.destroy(bufnr)
  assert(M.cache[bufnr]):destroy()
  M.cache[bufnr] = nil
end

return M
