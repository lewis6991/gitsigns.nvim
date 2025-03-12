local log = require('gitsigns.debug.log')
local async = require('gitsigns.async')
local util = require('gitsigns.util')
local Repo = require('gitsigns.git.repo')

local M = {}

M.Repo = Repo

--- @class Gitsigns.GitObj
--- @field file string
--- @field encoding string
--- @field i_crlf? boolean Object has crlf
--- @field w_crlf? boolean Working copy has crlf
--- @field mode_bits string
---
--- Revision the object is tracking against. Nil for index
--- @field revision? string
---
--- The fixed object name to use. Nil for untracked.
--- @field object_name? string
---
--- The path of the file relative to toplevel. Used to
--- perform git operations. Nil if file does not exist
--- @field relpath? string
---
--- Used for tracking moved files
--- @field orig_relpath? string
---
--- @field repo Gitsigns.Repo
--- @field has_conflicts? boolean
---
--- @field lock? true
local Obj = {}
Obj.__index = Obj

M.Obj = Obj

--- @param file string
--- @return boolean
local function in_git_dir(file)
  for _, p in ipairs(vim.split(file, util.path_sep)) do
    if p == '.git' then
      return true
    end
  end
  return false
end

--- @async
--- @param revision? string
--- @return string? err
function Obj:change_revision(revision)
  self.revision = util.norm_base(revision)
  return self:refresh()
end

--- @async
--- @return string? err
function Obj:refresh()
  local info, err = self.repo:file_info(self.file, self.revision)

  if err then
    log.eprint(err)
  end

  if not info then
    return err
  end

  self.relpath = info.relpath
  self.object_name = info.object_name
  self.mode_bits = info.mode_bits
  self.has_conflicts = info.has_conflicts
  self.i_crlf = info.i_crlf
  self.w_crlf = info.w_crlf
end

function Obj:from_tree()
  return Repo.from_tree(self.revision)
end

--- @async
--- @param revision? string
--- @return string[] stdout, string? stderr
function Obj:get_show_text(revision)
  if revision and not self.relpath then
    log.dprint('no relpath')
    return {}
  end

  local object = revision and (revision .. ':' .. self.relpath) or self.object_name

  if not object then
    log.dprint('no revision or object_name')
    return { '' }
  end

  local stdout, stderr = self.repo:get_show_text(object, self.encoding)

  if not self.i_crlf and self.w_crlf then
    -- Add cr
    -- Do not add cr to the newline at the end of file
    for i = 1, #stdout - 1 do
      stdout[i] = stdout[i] .. '\r'
    end
  end

  return stdout, stderr
end

--- @param file string
local function autocmd_changed(file)
  vim.schedule(function()
    vim.api.nvim_exec_autocmds('User', {
      pattern = 'GitSignsChanged',
      modeline = false,
      data = { file = file },
    })
  end)
end

--- @async
function Obj:unstage_file()
  self.lock = true
  self.repo:command({ 'reset', self.file })
  self.lock = nil
  autocmd_changed(self.file)
end

--- @async
--- @param contents? string[]
--- @param lnum? integer
--- @param revision? string
--- @param opts? Gitsigns.BlameOpts
--- @return table<integer,Gitsigns.BlameInfo?>
function Obj:run_blame(contents, lnum, revision, opts)
  return require('gitsigns.git.blame').run_blame(self, contents, lnum, revision, opts)
end

--- @async
--- @private
function Obj:ensure_file_in_index()
  self.lock = true
  if self.object_name and not self.has_conflicts then
    return
  end

  if not self.object_name then
    -- If there is no object_name then it is not yet in the index so add it
    self.repo:command({ 'add', '--intent-to-add', self.file })
  else
    -- Update the index with the common ancestor (stage 1) which is what bcache
    -- stores
    self.repo:update_index(self.mode_bits, self.object_name, self.relpath, true)
  end

  self:refresh()
  self.lock = nil
end

--- @async
--- Stage 'lines' as the entire contents of the file
--- @param lines string[]
function Obj:stage_lines(lines)
  self.lock = true
  local new_object = self.repo:hash_object(self.relpath, lines)
  self.repo:update_index(self.mode_bits, new_object, self.relpath)
  self.lock = nil
  autocmd_changed(self.file)
end

local sleep = async.awrap(2, function(duration, cb)
  vim.defer_fn(cb, duration)
end)

--- @async
--- @param hunks Gitsigns.Hunk.Hunk[]
--- @param invert? boolean
--- @return string? err
function Obj:stage_hunks(hunks, invert)
  self.lock = true
  self:ensure_file_in_index()

  local patch = require('gitsigns.hunks').create_patch(self.relpath, hunks, self.mode_bits, invert)

  if not self.i_crlf and self.w_crlf then
    -- Remove cr
    for i = 1, #patch do
      patch[i] = patch[i]:gsub('\r$', '')
    end
  end

  local stat, err = pcall(function()
    self.repo:command({
      'apply',
      '--whitespace=nowarn',
      '--cached',
      '--unidiff-zero',
      '-',
    }, {
      stdin = patch,
    })
  end)

  if not stat then
    self.lock = nil
    return err
  end

  -- Staging operations cause IO of the git directory so wait some time
  -- for the changes to settle.
  sleep(100)

  self.lock = nil
  autocmd_changed(self.file)
end

--- @async
--- @param file string
--- @param revision string?
--- @param encoding string
--- @param gitdir string?
--- @param toplevel string?
--- @return Gitsigns.GitObj?
function Obj.new(file, revision, encoding, gitdir, toplevel)
  -- TODO(lewis6991): this check is flawed as any directory can be a git-dir
  -- Can use: git rev-parse --is-inside-git-dir
  if in_git_dir(file) then
    log.dprint('In git dir')
    return
  end

  if not vim.startswith(file, '/') and toplevel then
    file = toplevel .. util.path_sep .. file
  end

  local repo = Repo.get(util.dirname(file), gitdir, toplevel)
  if not repo then
    log.dprint('Not in git repo')
    return
  end

  -- When passing gitdir and toplevel, suppress stderr when resolving the file
  local silent = gitdir ~= nil and toplevel ~= nil

  revision = util.norm_base(revision)

  local info, err = repo:file_info(file, revision)

  if err and not silent then
    log.eprint(err)
  end

  if not info then
    return
  end

  local self = setmetatable({}, Obj)
  self.repo = repo
  self.file = file
  self.revision = revision
  self.encoding = encoding

  self.relpath = info.relpath
  self.object_name = info.object_name
  self.mode_bits = info.mode_bits
  self.has_conflicts = info.has_conflicts
  self.i_crlf = info.i_crlf
  self.w_crlf = info.w_crlf

  return self
end

return M
