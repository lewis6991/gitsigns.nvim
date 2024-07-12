local log = require('gitsigns.debug.log')
local util = require('gitsigns.util')
local Repo = require('gitsigns.git.repo')

local check_version = require('gitsigns.git.version').check

local M = {}

M.Repo = Repo

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

--- @class Gitsigns.GitObj
--- @field file string
--- @field encoding string
--- @field i_crlf boolean Object has crlf
--- @field w_crlf boolean Working copy has crlf
--- @field mode_bits string
--- @field revision? string Revision the object is tracking against. Nil for index
--- @field object_name string The fixed object name to use.
--- @field relpath string
--- @field orig_relpath? string Use for tracking moved files
--- @field repo Gitsigns.Repo
--- @field has_conflicts? boolean
local Obj = {}

M.Obj = Obj

local git_command = require('gitsigns.git.cmd')

--- @async
--- @param file_cmp string
--- @param file_buf string
--- @param indent_heuristic? boolean
--- @param diff_algo string
--- @return string[] stdout, string? stderr
function M.diff(file_cmp, file_buf, indent_heuristic, diff_algo)
  return git_command({
    '-c',
    'core.safecrlf=false',
    'diff',
    '--color=never',
    '--' .. (indent_heuristic and '' or 'no-') .. 'indent-heuristic',
    '--diff-algorithm=' .. diff_algo,
    '--patch-with-raw',
    '--unified=0',
    file_cmp,
    file_buf,
  }, {
    -- git-diff implies --exit-code
    ignore_error = true,
  })
end

--- @param revision? string
function Obj:update_revision(revision)
  self.revision = util.norm_base(revision)
  self:update()
end

--- @param update_relpath? boolean
--- @param silent? boolean
--- @return boolean
function Obj:update(update_relpath, silent)
  local old_object_name = self.object_name
  local props = self:file_info(self.file, silent)

  if update_relpath then
    self.relpath = props.relpath
  end
  self.object_name = props.object_name
  self.mode_bits = props.mode_bits
  self.has_conflicts = props.has_conflicts
  self.i_crlf = props.i_crlf
  self.w_crlf = props.w_crlf

  return old_object_name ~= self.object_name
end

--- @class (exact) Gitsigns.FileInfo
--- @field relpath string
--- @field i_crlf? boolean
--- @field w_crlf? boolean
--- @field mode_bits? string
--- @field object_name? string
--- @field has_conflicts? true

function Obj:from_tree()
  return self.revision and not vim.startswith(self.revision, ':')
end

--- @param file? string
--- @param silent? boolean
--- @return Gitsigns.FileInfo
function Obj:file_info(file, silent)
  if self:from_tree() then
    return self:file_info_tree(file, silent)
  else
    return self:file_info_index(file, silent)
  end
end

--- @private
--- Get information about files in the index and the working tree
--- @param file? string
--- @param silent? boolean
--- @return Gitsigns.FileInfo
function Obj:file_info_index(file, silent)
  local has_eol = check_version({ 2, 9 })

  -- --others + --exclude-standard means ignored files won't return info, but
  -- untracked files will. Unlike file_info_tree which won't return untracked
  -- files.
  local cmd = {
    '-c',
    'core.quotepath=off',
    'ls-files',
    '--stage',
    '--others',
    '--exclude-standard',
  }

  if has_eol then
    cmd[#cmd + 1] = '--eol'
  end

  cmd[#cmd + 1] = file or self.file

  local results, stderr = self.repo:command(cmd, { ignore_error = true })

  if stderr and not silent then
    -- ignore_error for the cases when we run:
    --    git ls-files --others exists/nonexist
    if not stderr:match('^warning: could not open directory .*: No such file or directory') then
      log.eprint(stderr)
    end
  end

  local relpath_idx = has_eol and 2 or 1

  local result = {}
  for _, line in ipairs(results) do
    local parts = vim.split(line, '\t')
    if #parts > relpath_idx then -- tracked file
      local attrs = vim.split(parts[1], '%s+')
      local stage = tonumber(attrs[3])
      if stage <= 1 then
        result.mode_bits = attrs[1]
        result.object_name = attrs[2]
      else
        result.has_conflicts = true
      end

      if has_eol then
        result.relpath = parts[3]
        local eol = vim.split(parts[2], '%s+')
        result.i_crlf = eol[1] == 'i/crlf'
        result.w_crlf = eol[2] == 'w/crlf'
      else
        result.relpath = parts[2]
      end
    else -- untracked file
      result.relpath = parts[relpath_idx]
    end
  end

  return result
end

--- @private
--- Get information about files in a certain revision
--- @param file? string
--- @param silent? boolean
--- @return Gitsigns.FileInfo
function Obj:file_info_tree(file, silent)
  local results, stderr = self.repo:command({
    '-c',
    'core.quotepath=off',
    'ls-tree',
    self.revision,
    file or self.file,
  }, { ignore_error = true })

  if stderr then
    if not silent then
      log.eprint(stderr)
    end
    return {}
  end

  local info_line = results[1]
  if not info_line then
    return {}
  end

  local info, relpath = unpack(vim.split(info_line, '\t'))
  local mode_bits, objtype, object_name = unpack(vim.split(info, '%s+'))
  assert(objtype == 'blob')

  return {
    mode_bits = mode_bits,
    object_name = object_name,
    relpath = relpath,
  }
end

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

local function autocmd_changed(file)
  vim.schedule(function()
    vim.api.nvim_exec_autocmds('User', {
      pattern = 'GitSignsChanged',
      modeline = false,
      data = { file = file },
    })
  end)
end

function Obj:unstage_file()
  self.repo:command({ 'reset', self.file })
  autocmd_changed(self.file)
end

--- @param lines string[]
--- @param lnum? integer
--- @param revision? string
--- @param opts? Gitsigns.BlameOpts
--- @param progress_cb? fun(pct: number)
--- @return table<integer,Gitsigns.BlameInfo?>
function Obj:run_blame(lines, lnum, revision, opts, progress_cb)
  return require('gitsigns.git.blame').run_blame(self, lines, lnum, revision, opts, progress_cb)
end

--- @param obj Gitsigns.GitObj
local function ensure_file_in_index(obj)
  if obj.object_name and not obj.has_conflicts then
    return
  end

  if not obj.object_name then
    -- If there is no object_name then it is not yet in the index so add it
    obj.repo:command({ 'add', '--intent-to-add', obj.file })
  else
    -- Update the index with the common ancestor (stage 1) which is what bcache
    -- stores
    local info = string.format('%s,%s,%s', obj.mode_bits, obj.object_name, obj.relpath)
    obj.repo:command({ 'update-index', '--add', '--cacheinfo', info })
  end

  obj:update()
end

--- Stage 'lines' as the entire contents of the file
--- @param lines string[]
function Obj:stage_lines(lines)
  local new_object = self.repo:command({
    'hash-object',
    '-w',
    '--path',
    self.relpath,
    '--stdin',
  }, { stdin = lines })[1]

  self.repo:command({
    'update-index',
    '--cacheinfo',
    string.format('%s,%s,%s', self.mode_bits, new_object, self.relpath),
  })

  autocmd_changed(self.file)
end

--- @param hunks Gitsigns.Hunk.Hunk[]
--- @param invert? boolean
function Obj:stage_hunks(hunks, invert)
  ensure_file_in_index(self)

  local patch = require('gitsigns.hunks').create_patch(self.relpath, hunks, self.mode_bits, invert)

  if not self.i_crlf and self.w_crlf then
    -- Remove cr
    for i = 1, #patch do
      patch[i] = patch[i]:gsub('\r$', '')
    end
  end

  self.repo:command({
    'apply',
    '--whitespace=nowarn',
    '--cached',
    '--unidiff-zero',
    '-',
  }, {
    stdin = patch,
  })

  autocmd_changed(self.file)
end

--- @return string?
function Obj:has_moved()
  local out = self.repo:command({ 'diff', '--name-status', '-C', '--cached' })
  local orig_relpath = self.orig_relpath or self.relpath
  for _, l in ipairs(out) do
    local parts = vim.split(l, '%s+')
    if #parts == 3 then
      local orig, new = parts[2], parts[3]
      if orig_relpath == orig then
        self.orig_relpath = orig_relpath
        self.relpath = new
        self.file = self.repo.toplevel .. '/' .. new
        return new
      end
    end
  end
end

--- @param file string
--- @param revision string?
--- @param encoding string
--- @param gitdir string?
--- @param toplevel string?
--- @return Gitsigns.GitObj?
function Obj.new(file, revision, encoding, gitdir, toplevel)
  if in_git_dir(file) then
    log.dprint('In git dir')
    return nil
  end

  if not vim.startswith(file, '/') and toplevel then
    file = toplevel .. util.path_sep .. file
  end

  local repo = Repo.get(util.dirname(file), gitdir, toplevel)
  if not repo then
    log.dprint('Not in git repo')
    return
  end

  local self = setmetatable({}, { __index = Obj })
  self.repo = repo
  self.file = file
  self.revision = util.norm_base(revision)
  self.encoding = encoding

  -- When passing gitdir and toplevel, suppress stderr when resolving the file
  local silent = gitdir ~= nil and toplevel ~= nil

  self:update(true, silent)

  return self
end

return M
