local async = require('gitsigns.async')
local git_command = require('gitsigns.git.cmd')
local log = require('gitsigns.debug.log')
local util = require('gitsigns.util')

local system = require('gitsigns.system').system
local check_version = require('gitsigns.git.version').check

local uv = vim.uv or vim.loop

--- @class Gitsigns.RepoInfo
--- @field gitdir string
--- @field toplevel string
--- @field detached boolean
--- @field abbrev_head string

--- @class Gitsigns.Repo : Gitsigns.RepoInfo
---
--- Username configured for the repo.
--- Needed for to determine "You" in current line blame.
--- @field username string
local M = {}

--- Run git command the with the objects gitdir and toplevel
--- @async
--- @param args table<any,any>
--- @param spec? Gitsigns.Git.JobSpec
--- @return string[] stdout
--- @return string? stderr
--- @return integer code
function M:command(args, spec)
  spec = spec or {}
  spec.cwd = self.toplevel

  return git_command({
    '--git-dir',
    self.gitdir,
    self.detached and { '--work-tree', self.toplevel },
    args,
  }, spec)
end

--- @param base string?
--- @return string[]
function M:files_changed(base)
  if base and base ~= ':0' then
    local results = self:command({ 'diff', '--name-status', base })
    for i, result in ipairs(results) do
      results[i] = vim.split(result:gsub('\t', ' '), ' ', { plain = true })[2]
    end
    return results
  end

  local results = self:command({ 'status', '--porcelain', '--ignore-submodules' })

  local ret = {} --- @type string[]
  for _, line in ipairs(results) do
    if line:sub(1, 2):match('^.M') then
      ret[#ret + 1] = line:sub(4, -1)
    end
  end
  return ret
end

--- @param encoding string
--- @return boolean
local function iconv_supported(encoding)
  -- TODO(lewis6991): needs https://github.com/neovim/neovim/pull/21924
  if vim.startswith(encoding, 'utf-16') or vim.startswith(encoding, 'utf-32') then
    return false
  end
  return true
end

--- @async
--- Get version of file in the index, return array lines
--- @param object string
--- @param encoding? string
--- @return string[] stdout, string? stderr
function M:get_show_text(object, encoding)
  local stdout, stderr = self:command({ 'show', object }, { text = false, ignore_error = true })

  if encoding and encoding ~= 'utf-8' and iconv_supported(encoding) then
    for i, l in ipairs(stdout) do
      stdout[i] = vim.iconv(l, encoding, 'utf-8')
    end
  end

  return stdout, stderr
end

--- @async
function M:update_abbrev_head()
  local info, err = M.get_info(self.toplevel)
  if not info then
    log.eprintf('Could not get info for repo at %s: %s', self.gitdir, err or '')
    return
  end
  self.abbrev_head = info.abbrev_head
end

--- @async
--- @private
--- @param info Gitsigns.RepoInfo
--- @return Gitsigns.Repo
local function new(info)
  local self = setmetatable({}, { __index = M })
  for k, v in
    pairs(info --[[@as table<string,any>]])
  do
    ---@diagnostic disable-next-line:no-unknown
    self[k] = v
  end

  self.username = self:command({ 'config', 'user.name' }, { ignore_error = true })[1]

  return self
end

--- @type table<string,[integer,Gitsigns.Repo]?>
local repo_cache = setmetatable({}, { __mode = 'v' })

--- @async
--- @param dir string
--- @param gitdir? string
--- @param toplevel? string
--- @return Gitsigns.Repo?
function M.get(dir, gitdir, toplevel)
  local info = M.get_info(dir, gitdir, toplevel)
  if not info then
    return
  end

  gitdir = info.gitdir
  if not repo_cache[gitdir] then
    repo_cache[gitdir] = { 1, new(info) }
  else
    repo_cache[gitdir][1] = repo_cache[gitdir][1] + 1
  end

  return repo_cache[gitdir][2]
end

function M:unref()
  local gitdir = self.gitdir
  local repo = repo_cache[gitdir]
  if not repo then
    -- Already reclaimed by GC
    return
  end
  local refcount = repo[1]
  if refcount <= 1 then
    repo_cache[gitdir] = nil
  else
    repo_cache[gitdir][1] = refcount - 1
  end
end

local has_cygpath = jit and jit.os == 'Windows' and vim.fn.executable('cygpath') == 1

--- @async
--- @generic S
--- @param path S
--- @return S
local function normalize_path(path)
  if path and has_cygpath and not uv.fs_stat(path) then
    -- If on windows and path isn't recognizable as a file, try passing it
    -- through cygpath
    --- @type string
    path = async.await(3, system, { 'cygpath', '-aw', path }).stdout
  end
  return path
end

--- @async
--- @param gitdir? string
--- @param head_str string
--- @param cwd string
--- @return string
local function process_abbrev_head(gitdir, head_str, cwd)
  if not gitdir or head_str ~= 'HEAD' then
    return head_str
  end

  local short_sha = git_command({ 'rev-parse', '--short', 'HEAD' }, {
    ignore_error = true,
    cwd = cwd,
  })[1] or ''

  if log.debug_mode and short_sha ~= '' then
    short_sha = 'HEAD'
  end

  if util.path_exists(gitdir .. '/rebase-merge') or util.path_exists(gitdir .. '/rebase-apply') then
    return short_sha .. '(rebasing)'
  end

  return short_sha
end

--- @async
--- @param cwd string
--- @param gitdir? string
--- @param worktree? string
--- @return Gitsigns.RepoInfo? info, string? err
function M.get_info(cwd, gitdir, worktree)
  -- Does git rev-parse have --absolute-git-dir, added in 2.13:
  --    https://public-inbox.org/git/20170203024829.8071-16-szeder.dev@gmail.com/
  local has_abs_gd = check_version(2, 13)

  -- Wait for internal scheduler to settle before running command (#215)
  async.schedule()

  -- gitdir and worktree must be provided together from `man git`:
  -- > Specifying the location of the ".git" directory using this option (or GIT_DIR environment
  -- > variable) turns off the repository discovery that tries to find a directory with ".git"
  -- > subdirectory (which is how the repository and the top-level of the working tree are
  -- > discovered), and tells Git that you are at the top level of the working tree. If you are
  -- > not at the top-level directory of the working tree, you should tell Git where the
  -- > top-level of the working tree is, with the --work-tree=<path> option (or GIT_WORK_TREE
  -- > environment variable)
  local stdout, stderr, code = git_command({
    gitdir and worktree and {
      '--git-dir',
      gitdir,
      '--work-tree',
      worktree,
    },
    'rev-parse',
    '--show-toplevel',
    has_abs_gd and '--absolute-git-dir' or '--git-dir',
    '--abbrev-ref',
    'HEAD',
  }, {
    ignore_error = true,
    cwd = worktree or cwd,
  })

  -- If the repo has no commits yet, rev-parse will fail. Ignore this error.
  if code > 0 and stderr and stderr:match("fatal: ambiguous argument 'HEAD'") then
    code = 0
  end

  if code > 0 then
    return nil, string.format('got stderr: %s', stderr or '')
  end

  if #stdout < 3 then
    return nil, string.format('incomplete stdout: %s', table.concat(stdout, '\n'))
  end

  local toplevel_r = assert(normalize_path(stdout[1]))
  local gitdir_r = assert(normalize_path(stdout[2]))

  if not has_abs_gd then
    gitdir_r = assert(uv.fs_realpath(gitdir_r))
  end

  if gitdir and not worktree and gitdir ~= gitdir_r then
    log.eprintf('expected gitdir to be %s, got %s', gitdir, gitdir_r)
  end

  return {
    toplevel = toplevel_r,
    gitdir = gitdir_r,
    abbrev_head = process_abbrev_head(gitdir_r, assert(stdout[3]), cwd),
    detached = toplevel_r and gitdir_r ~= toplevel_r .. '/.git',
  }
end

--- @class (exact) Gitsigns.Repo.LsTree.Result
--- @field relpath string
--- @field mode_bits? string
--- @field object_name? string
--- @field object_type? 'blob'|'tree'|'commit'

--- @param path string
--- @param revision string
--- @return Gitsigns.Repo.LsTree.Result? info
--- @return string? err
function M:ls_tree(path, revision)
  local results, stderr, code = self:command({
    '-c',
    'core.quotepath=off',
    'ls-tree',
    revision,
    path,
  }, { ignore_error = true })

  if code > 0 then
    return nil, stderr or tostring(code)
  end

  local info, relpath = unpack(vim.split(results[1], '\t'))
  local mode_bits, object_type, object_name = unpack(vim.split(info, '%s+'))

  return {
    relpath = relpath,
    mode_bits = mode_bits,
    object_name = object_name,
    object_type = object_type,
  }
end

--- @class (exact) Gitsigns.Repo.LsFiles.Result
--- @field relpath? string nil if file is not in working tree
--- @field mode_bits? string
--- @field object_name? string nil if file is untracked
--- @field i_crlf? boolean (requires git version >= 2.9)
--- @field w_crlf? boolean (requires git version >= 2.9)
--- @field has_conflicts? true

--- @async
--- Get information about files in the index and the working tree
--- @param file string
--- @return Gitsigns.Repo.LsFiles.Result? info
--- @return string? err
function M:ls_files(file)
  local has_eol = check_version(2, 9)

  -- --others + --exclude-standard means ignored files won't return info, but
  -- untracked files will. Unlike file_info_tree which won't return untracked
  -- files.
  local results, stderr, code = self:command({
    '-c',
    'core.quotepath=off',
    'ls-files',
    '--stage',
    '--others',
    '--exclude-standard',
    has_eol and '--eol',
    file,
  }, { ignore_error = true })

  -- ignore_error for the cases when we run:
  --    git ls-files --others exists/nonexist
  if
    code > 0
    and (
      not stderr
      or not stderr:match('^warning: could not open directory .*: No such file or directory')
    )
  then
    return nil, stderr or tostring(code)
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

--- @param revision? string
--- @return boolean
function M.from_tree(revision)
  return revision ~= nil and not vim.startswith(revision, ':')
end

--- @async
--- @param file string
--- @param revision? string
--- @return Gitsigns.Repo.LsFiles.Result? info
--- @return string? err
function M:file_info(file, revision)
  if M.from_tree(revision) then
    local info, err = self:ls_tree(file, assert(revision))
    if err then
      return nil, err
    end

    if info and info.object_type == 'blob' then
      return {
        relpath = info.relpath,
        mode_bits = info.mode_bits,
        object_name = info.object_name,
      }
    end
  else
    local info, err = self:ls_files(file)
    if err then
      return nil, err
    end

    return info
  end
end

--- @param mode_bits string
--- @param object string
--- @param path string
--- @param add? boolean
function M:update_index(mode_bits, object, path, add)
  self:command({
    'update-index',
    add and '--add',
    '--cacheinfo',
    ('%s,%s,%s'):format(mode_bits, object, path),
  })
end

--- @param path string
--- @param lines string[]
--- @return string
function M:hash_object(path, lines)
  -- Concatenate the lines into a single string to ensure EOL
  -- is respected
  local text = table.concat(lines, '\n')
  return self:command({ 'hash-object', '-w', '--path', path, '--stdin' }, { stdin = text })[1]
end

--- @async
--- @return string[]
function M:rename_status()
  local out = self:command({
    'diff',
    '--name-status',
    '--find-renames',
    '--find-copies',
    '--cached',
  })
  local ret = {} --- @type table<string,string>
  for _, l in ipairs(out) do
    local parts = vim.split(l, '%s+')
    if #parts == 3 then
      local stat, orig_file, new_file = parts[1], parts[2], parts[3]
      if vim.startswith(stat, 'R') then
        ret[orig_file] = new_file
      end
    end
  end
  return ret
end

return M
