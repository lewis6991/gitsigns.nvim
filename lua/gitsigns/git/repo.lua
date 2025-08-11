local async = require('gitsigns.async')
local git_command = require('gitsigns.git.cmd')
local log = require('gitsigns.debug.log')
local util = require('gitsigns.util')
local errors = require('gitsigns.git.errors')
local debounce_trailing = require('gitsigns.debounce').debounce_trailing

local check_version = require('gitsigns.git.version').check

local uv = vim.uv or vim.loop ---@diagnostic disable-line: deprecated

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
--- @field package _watcher_callbacks table<fun(),true>
--- @field package _watcher uv.uv_fs_event_t
--- @field package _gc userdata Used for garbage collection
local M = {}

--- vim.inspect but on one line
--- @param x any
--- @return string
local function inspect(x)
  return vim.inspect(x, { indent = '', newline = ' ' })
end

--- @param cb fun()
--- @return fun() deregister
function M:register_callback(cb)
  self._watcher_callbacks[cb] = true

  return function()
    self._watcher_callbacks[cb] = nil
  end
end

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

  local args0 = { '--git-dir', self.gitdir }

  if self.detached then
    -- If detached, we need to set the work tree to the toplevel so that git
    -- commands work correctly.
    args0 = vim.list_extend(args0, { '--work-tree', self.toplevel })
  end

  vim.list_extend(args0, args)

  return git_command(args0, spec)
end

--- @async
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
--- @package
function M:update_abbrev_head()
  local info, err = M.get_info(self.toplevel)
  if not info then
    log.eprintf('Could not get info for repo at %s: %s', self.gitdir, err or '')
    return
  end
  self.abbrev_head = info.abbrev_head
end

--- @type table<string,Gitsigns.Repo?>
local repo_cache = setmetatable({}, { __mode = 'v' })

--- @param fn fun()
--- @return userdata
local function gc_proxy(fn)
  local proxy = newproxy(true)
  getmetatable(proxy).__gc = fn
  return proxy
end

--- @generic T1, T, R
--- @param fn fun(_:T1, _:T...): R...
--- @param arg1 T1
--- @return fun(_:T...): R...
local function curry1(fn, arg1)
  return function(...)
    return fn(arg1, ...)
  end
end

--- @param gitdir string
--- @param err? string
--- @param filename string
--- @param events { change?: boolean, rename?: boolean }
local function watcher_cb(gitdir, err, filename, events)
  local __FUNC__ = 'watcher_cb'
  -- do not use `self` here as it prevents garbage collection. Must use a
  -- weak reference.
  local repo = repo_cache[gitdir]
  if not repo then
    return -- garbage collected
  end

  if err then
    log.dprintf('Git dir update error: %s', err)
    return
  end

  -- The luv docs say filename is passed as a string but it has been observed
  -- to sometimes be nil.
  --    https://github.com/lewis6991/gitsigns.nvim/issues/848
  if not filename then
    log.eprint('No filename')
    return
  end

  log.dprintf("Git dir update: '%s' %s", filename, inspect(events))

  if vim.startswith(filename, '.watchman-cookie') then
    return
  end

  async.run(function()
    repo:update_abbrev_head()

    for cb in pairs(repo._watcher_callbacks) do
      vim.schedule(cb)
    end
  end)
end

--- @async
--- @private
--- @param info Gitsigns.RepoInfo
--- @return Gitsigns.Repo
local function new(info)
  local self = setmetatable(info, { __index = M })
  --- @cast self Gitsigns.Repo

  self.username = self:command({ 'config', 'user.name' }, { ignore_error = true })[1]

  do -- gitdir watcher
    self._watcher_callbacks = {}
    self._watcher = assert(uv.new_fs_event())

    local debounced_handler = debounce_trailing(1000, curry1(watcher_cb, self.gitdir))
    self._watcher:start(self.gitdir, {}, debounced_handler)

    self._gc = gc_proxy(function()
      self._watcher:stop()
      self._watcher:close()
    end)
  end

  return self
end

local sem = async.semaphore(1)

--- @async
--- @param cwd? string
--- @param gitdir? string
--- @param toplevel? string
--- @return Gitsigns.Repo? repo
--- @return string? err
function M.get(cwd, gitdir, toplevel)
  --- EmmyLuaLs/emmylua-analyzer-rust#659
  --- @return Gitsigns.Repo? repo
  --- @return string? err
  return sem:with(function()
    local info, err = M.get_info(cwd, gitdir, toplevel)
    if not info then
      return nil, err
    end

    repo_cache[info.gitdir] = repo_cache[info.gitdir] or new(info)
    return repo_cache[info.gitdir]
  end)
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

  if short_sha ~= '' and log.debug_mode() then
    short_sha = 'HEAD'
  end

  if
    util.Path.exists(util.Path.join(gitdir, 'rebase-merge'))
    or util.Path.exists(util.Path.join(gitdir, 'rebase-apply'))
  then
    return short_sha .. '(rebasing)'
  end

  return short_sha
end

--- @async
--- @param dir? string
--- @param gitdir? string
--- @param worktree? string
--- @return Gitsigns.RepoInfo? info, string? err
function M.get_info(dir, gitdir, worktree)
  -- Does git rev-parse have --absolute-git-dir, added in 2.13:
  --    https://public-inbox.org/git/20170203024829.8071-16-szeder.dev@gmail.com/
  local has_abs_gd = check_version(2, 13)

  -- Wait for internal scheduler to settle before running command (#215)
  async.schedule()

  if dir and not uv.fs_stat(dir) then
    -- Cwd can be deleted externally, so check if it exists (see #1331)
    log.dprintf("dir '%s' does not exist", dir)
    return
  end

  -- Explicitly fallback to env vars for better debug
  gitdir = gitdir or vim.env.GIT_DIR
  worktree = worktree or vim.env.GIT_WORK_TREE or vim.fs.dirname(gitdir)

  -- gitdir and worktree must be provided together from `man git`:
  -- > Specifying the location of the ".git" directory using this option (or GIT_DIR environment
  -- > variable) turns off the repository discovery that tries to find a directory with ".git"
  -- > subdirectory (which is how the repository and the top-level of the working tree are
  -- > discovered), and tells Git that you are at the top level of the working tree. If you are
  -- > not at the top-level directory of the working tree, you should tell Git where the
  -- > top-level of the working tree is, with the --work-tree=<path> option (or GIT_WORK_TREE
  -- > environment variable)
  local stdout, stderr, code = git_command(
    util.flatten({
      gitdir and { '--git-dir', gitdir },
      worktree and { '--work-tree', worktree },
      'rev-parse',
      '--show-toplevel',
      has_abs_gd and '--absolute-git-dir' or '--git-dir',
      '--abbrev-ref',
      'HEAD',
    }),
    {
      ignore_error = true,
      -- Worktree may be a relative path, so don't set cwd when it is provided.
      cwd = not worktree and dir or nil,
    }
  )

  -- If the repo has no commits yet, rev-parse will fail. Ignore this error.
  if code > 0 and stderr and stderr:match(errors.e.ambiguous_head) then
    code = 0
  end

  if code > 0 then
    return nil, string.format('got stderr: %s', stderr or '')
  end

  if #stdout < 3 then
    return nil, string.format('incomplete stdout: %s', table.concat(stdout, '\n'))
  end
  --- @cast stdout [string, string, string]

  local toplevel_r = stdout[1]
  local gitdir_r = stdout[2]

  -- On windows, git will emit paths with `/` but dir may contain `\` so need to
  -- normalize.
  if dir and not vim.startswith(vim.fs.normalize(dir), toplevel_r) then
    log.dprintf("'%s' is outside worktree '%s'", dir, toplevel_r)
    -- outside of worktree
    return
  end

  if not has_abs_gd then
    gitdir_r = assert(uv.fs_realpath(gitdir_r))
  end

  if gitdir and not worktree and gitdir ~= gitdir_r then
    log.eprintf('expected gitdir to be %s, got %s', gitdir, gitdir_r)
  end

  return {
    toplevel = toplevel_r,
    gitdir = gitdir_r,
    abbrev_head = process_abbrev_head(gitdir_r, stdout[3], toplevel_r),
    detached = toplevel_r and gitdir_r ~= toplevel_r .. '/.git',
  }
end

--- @class (exact) Gitsigns.Repo.LsTree.Result
--- @field relpath string
--- @field mode_bits? string
--- @field object_name? string
--- @field object_type? 'blob'|'tree'|'commit'

--- @async
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

  local res = results[1]

  if not res then
    -- Not found, see if it was renamed
    log.dprintf('%s not found in %s looking for renames', path, revision)
    local old_path = self:diff_rename_status(revision, true)[path]
    if old_path then
      log.dprintf('found rename %s -> %s', old_path, path)
      return self:ls_tree(old_path, revision)
    end

    return nil, ('%s not found in %s'):format(path, revision)
  end

  local info, relpath = unpack(vim.split(res, '\t'))
  assert(info and relpath)
  local mode_bits, object_type, object_name = unpack(vim.split(info, '%s+'))
  --- @cast object_type 'blob'|'tree'|'commit'

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
  local results, stderr, code = self:command(
    util.flatten({
      '-c',
      'core.quotepath=off',
      'ls-files',
      '--stage',
      '--others',
      '--exclude-standard',
      has_eol and '--eol',
      file,
    }),
    { ignore_error = true }
  )

  -- ignore_error for the cases when we run:
  --    git ls-files --others exists/nonexist
  if code > 0 and (not stderr or not stderr:match(errors.e.path_does_not_exist)) then
    return nil, stderr or tostring(code)
  end

  local relpath_idx = has_eol and 2 or 1

  local result = {}
  for _, line in ipairs(results) do
    local parts = vim.split(line, '\t')
    if #parts > relpath_idx then -- tracked file
      local attrs = vim.split(assert(parts[1]), '%s+')
      local stage = tonumber(attrs[3])
      if stage <= 1 then
        result.mode_bits = attrs[1]
        result.object_name = attrs[2]
      else
        result.has_conflicts = true
      end

      if has_eol then
        result.relpath = parts[3]
        local eol = vim.split(assert(parts[2]), '%s+')
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

--- @async
--- @param mode_bits string
--- @param object string
--- @param path string
--- @param add? boolean
function M:update_index(mode_bits, object, path, add)
  self:command(util.flatten({
    'update-index',
    add and '--add',
    '--cacheinfo',
    ('%s,%s,%s'):format(mode_bits, object, path),
  }))
end

--- @async
--- @param path string
--- @param lines string[]
--- @return string
function M:hash_object(path, lines)
  -- Concatenate the lines into a single string to ensure EOL
  -- is respected
  local text = table.concat(lines, '\n')
  local res = self:command({ 'hash-object', '-w', '--path', path, '--stdin' }, { stdin = text })[1]
  return assert(res)
end

--- @async
--- @param revision string
--- @param path string
--- @return string?
function M:log_rename_status(revision, path)
  local out = self:command({
    'log',
    '--follow',
    '--name-status',
    '--diff-filter=R',
    '--format=',
    revision .. '..HEAD',
    '--',
    path,
  })
  local line = out[#out]
  if not line then
    return
  end
  return vim.split(line, '%s+')[2]
end

--- @async
--- @param revision? string
--- @param invert? boolean
--- @return table<string,string>
function M:diff_rename_status(revision, invert)
  local out = self:command({
    'diff',
    '--name-status',
    '--find-renames',
    '--find-copies',
    '--cached',
    revision,
  })
  local ret = {} --- @type table<string,string>
  for _, l in ipairs(out) do
    local parts = vim.split(l, '%s+')
    if #parts == 3 then
      --- @cast parts [string, string, string]
      local stat, orig_file, new_file = parts[1], parts[2], parts[3]
      if vim.startswith(stat, 'R') then
        if invert then
          ret[new_file] = orig_file
        else
          ret[orig_file] = new_file
        end
      end
    end
  end
  return ret
end

return M
