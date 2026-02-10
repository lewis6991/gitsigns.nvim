local async = require('gitsigns.async')
local git_command = require('gitsigns.git.cmd')
local config = require('gitsigns.config').config
local log = require('gitsigns.debug.log')
local util = require('gitsigns.util')
local Path = util.Path
local errors = require('gitsigns.git.errors')
local Watcher = require('gitsigns.git.repo.watcher')

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
--- @field private _watcher? Gitsigns.Repo.Watcher
--- @field head_oid? string
--- @field head_ref? string
--- @field commondir string
local M = {}

--- @param gitdir string
--- @return boolean
local function is_rebasing(gitdir)
  return Path.exists(Path.join(gitdir, 'rebase-merge'))
    or Path.exists(Path.join(gitdir, 'rebase-apply'))
end

--- @param value string?
--- @return string?
local function trim(value)
  if not value then
    -- Preserve nil to signal "no value".
    return
  end
  -- Normalize line endings/whitespace from ref files.
  local trimmed = vim.trim(value)
  -- Treat whitespace-only lines as absent.
  return trimmed ~= '' and trimmed or nil
end

--- @param path string
--- @return string?
local function read_first_line(path)
  local f = io.open(path, 'r')
  if not f then
    return
  end
  local line = f:read('*l')
  f:close()
  return trim(line)
end

--- @param path string
local function wait_for_unlock(path)
  -- Git updates refs by taking `<ref>.lock` and then renaming into place.
  -- Wait briefly so we don't read transient state when reacting to fs events.
  --
  -- TODO(lewis6991): should this be async?
  vim.wait(1000, function()
    return not Path.exists(path .. '.lock')
  end, 10, true)
end

--- Wait for `<path>.lock` to clear then read the first line of a file.
--- @param path string
--- @return string?
local function read_first_line_wait(path)
  wait_for_unlock(path)
  return read_first_line(path)
end

--- @param gitdir string
--- @return string?
local function read_head(gitdir)
  return read_first_line_wait(Path.join(gitdir, 'HEAD'))
end

--- @param head string?
--- @return string?
local function parse_head_ref(head)
  return head and head:match('^ref:%s*(.+)$') or nil
end

--- Return the abbreviated ref for HEAD (or short SHA if detached).
--- Equivalent to `git rev-parse --abbrev-ref HEAD`
--- @param gitdir string Must be an absolute path to the .git directory
--- @param head? string
--- @return string abbrev_head
local function get_abbrev_head(gitdir, head)
  head = head or assert(read_head(gitdir))
  -- HEAD content is either:
  --   "ref: refs/heads/<branch>"
  --   "<commitsha>" (detached HEAD)
  local refpath = parse_head_ref(head)
  if refpath then
    -- Extract last path component (branch name)
    return refpath:match('([^/]+)$') or refpath
  end

  assert(head:find('^[%x]+$'), 'Invalid HEAD content: ' .. head)

  -- Detached HEAD -> like `git rev-parse --abbrev-ref HEAD`, return literal "HEAD"
  local short_sha = log.debug_mode() and 'HEAD' or head:sub(1, 7)

  if is_rebasing(gitdir) then
    short_sha = short_sha .. '(rebasing)'
  end
  return short_sha
end

--- @param gitdir string
--- @return string
local function get_commondir(gitdir)
  -- In linked worktrees, `gitdir` points at `.git/worktrees/<name>` while most
  -- refs live under the main `.git` directory (the "commondir").
  local commondir = read_first_line(Path.join(gitdir, 'commondir'))
  if not commondir then
    return gitdir
  end
  local abs = Path.join(gitdir, commondir)
  return uv.fs_realpath(abs) or abs
end

--- @param commondir string
--- @param refname string
--- @return string?
local function read_packed_ref(commondir, refname)
  local packed_refs_path = Path.join(commondir, 'packed-refs')
  wait_for_unlock(packed_refs_path)
  -- `packed-refs` is a flat map from refname to OID (with optional peeled
  -- entries). Read it linearly as this is only used on debounced fs events.
  local f = io.open(packed_refs_path, 'r')
  if not f then
    return
  end
  for line in f:lines() do
    --- @cast line string
    if line:sub(1, 1) ~= '#' and line:sub(1, 1) ~= '^' then
      local oid, name = line:match('^(%x+)%s+(.+)$')
      if name == refname then
        f:close()
        return oid
      end
    end
  end
  f:close()
end

--- @param gitdir string
--- @param commondir? string
--- @param refname string
--- @return string?
local function resolve_ref(gitdir, commondir, refname)
  -- Resolve a refname to an OID by following symbolic refs and checking:
  -- - worktree-local loose refs in `gitdir/`
  -- - shared loose refs in `commondir/`
  -- - `commondir/packed-refs`
  local seen = {} --- @type table<string, true>
  local current = refname

  while current and current ~= '' do
    if seen[current] then
      log.dprintf('cycle detected in symbolic refs: %s', vim.inspect(vim.tbl_keys(seen)))
      return
    end
    seen[current] = true

    local line = read_first_line_wait(Path.join(gitdir, current))

    if not line and commondir and commondir ~= gitdir then
      line = read_first_line_wait(Path.join(commondir, current))
    end

    if not line then
      log.dprintf('Ref %s not found as loose ref; checking packed-refs', current)
      break
    elseif line:match('^%x+$') then
      return line
    end

    local symref = line:match('^ref:%s*(.+)$')
    if symref then
      current = symref
    else
      log.dprintf('Ref %s has invalid contents (%s); checking packed-refs', current, line)
      break
    end
  end

  if commondir and current then
    -- Some refs are only stored in packed-refs.
    local packed = read_packed_ref(commondir, current)
    if packed and packed:match('^%x+$') then
      return packed
    end
  end
end

--- Manual implementation of `git rev-parse HEAD`.
--- @param gitdir string
--- @param commondir string
--- @return string? oid
--- @return string? err
local function get_head_oid0(gitdir, commondir)
  -- `.git/HEAD` can remain unchanged while its target ref moves (e.g. `git pull`
  -- updating the checked-out branch). Resolve `HEAD` through loose refs and
  -- packed-refs so we can detect branch moves without spawning `git`.
  local head = read_head(gitdir)
  if not head then
    -- Unable to read HEAD.
    return nil, 'unable to read HEAD file'
  end

  if head:match('^%x+$') then
    -- Detached HEAD contains an OID directly.
    return head
  end

  local ref = parse_head_ref(head)
  if not ref then
    -- Unrecognized HEAD format.
    return nil, ('unrecognized HEAD contents: %s'):format(head)
  end

  local oid = resolve_ref(gitdir, commondir, ref)
  if oid then
    -- Resolved via loose refs or packed-refs.
    return oid
  end

  -- Reftable stores refs in a different backend (no loose/packed refs).
  if Path.exists(Path.join(commondir, 'reftable')) then
    return nil, 'reftable'
  end

  -- Reftable cannot be parsed via loose refs/packed-refs. Keep a synchronous
  -- fallback for correctness (rare setup). Some other backends or transient
  -- states can also cause resolution to fail, so keep this as a general
  -- fallback.
  return nil, ('unable to resolve %s via loose refs/packed-refs'):format(ref)
end

--- Manual implementation of `git rev-parse HEAD` with command fallback.
--- @param gitdir string
--- @param commondir string
--- @return string? oid
local function get_head_oid(gitdir, commondir)
  local oid0, err = get_head_oid0(gitdir, commondir)
  if oid0 then
    return oid0
  end

  log.dprintf('Falling back to `git rev-parse HEAD`: %s', err)

  local stdout, stderr, code = async
    .run(git_command, { '--git-dir', gitdir, 'rev-parse', 'HEAD' }, { ignore_error = true })
    :wait()

  local oid = stdout[1]

  if code ~= 0 or not oid or not oid:match('^%x+$') then
    log.dprintf('Fallback `git rev-parse HEAD` failed: code=%s oid=%s stderr=%s', code, oid, stderr)
    return
  end
  return oid
end

--- Registers a callback to be invoked on update events.
---
--- The provided callback function `cb` will be stored and called when an update
--- occurs. Returns a deregister function that, when called, will remove the
--- callback from the watcher.
---
--- @param callback fun() Callback function to be invoked on update.
--- @return fun() deregister Function to remove the callback from the watcher.
function M:on_update(callback)
  assert(self._watcher, 'Watcher not initialized')
  return self._watcher:on_update(callback)
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
--- @param include_untracked? boolean
--- @return string[]
function M:files_changed(base, include_untracked)
  if base and base ~= ':0' then
    local results = self:command({ 'diff', '--name-status', base })
    for i, result in ipairs(results) do
      results[i] = vim.split(result:gsub('\t', ' '), ' ', { plain = true })[2]
    end
    if include_untracked then
      local untracked = self:command({ 'ls-files', '--others', '--exclude-standard' })
      vim.list_extend(results, untracked)
    end
    return results
  end

  local results = self:command({ 'status', '--porcelain', '--ignore-submodules' })

  local ret = {} --- @type string[]
  for _, line in ipairs(results) do
    local status = line:sub(1, 2)
    if status:match('^.M') or (include_untracked and status == '??') then
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

--- @type table<string,Gitsigns.Repo?>
local repo_cache = setmetatable({}, { __mode = 'v' })

--- @async
--- @private
--- @param info Gitsigns.RepoInfo
--- @return Gitsigns.Repo
function M._new(info)
  --- @type Gitsigns.Repo
  local self = setmetatable(info, { __index = M })
  self.username = self:command({ 'config', 'user.name' }, { ignore_error = true })[1]

  self.commondir = get_commondir(self.gitdir)

  if config.watch_gitdir.enable then
    local head = read_head(self.gitdir)
    self.head_ref = parse_head_ref(head)
    self.head_oid = get_head_oid(self.gitdir, self.commondir)
    self._watcher = Watcher.new(self.gitdir, self.commondir)
    self._watcher:set_head_ref(self.head_ref)
    self._watcher:on_update(function()
      -- Recompute on every debounced tick. The checked-out branch can move
      -- without `HEAD` changing (e.g. `refs/heads/main` update).
      local head2 = read_head(self.gitdir)
      if not head2 then
        return
      end

      self.head_oid = get_head_oid(self.gitdir, self.commondir)
      -- Set abbrev_head to empty string if head_oid is unavailable (.e.g repo
      -- with no commits). This is consistent with `git rev-parse --abrev-ref
      -- HEAD` which returns "HEAD" in this case.
      local abbrev_head = self.head_oid and get_abbrev_head(self.gitdir, head2) or ''
      if self.abbrev_head ~= abbrev_head then
        self.abbrev_head = abbrev_head
        log.dprintf('HEAD changed, updating abbrev_head to %s', self.abbrev_head)
      end

      local head_ref = parse_head_ref(head2)
      if self.head_ref ~= head_ref then
        self.head_ref = head_ref
        self._watcher:set_head_ref(self.head_ref)
      end
    end)
  end

  return self
end

function M:has_watcher()
  return self._watcher ~= nil
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

    repo_cache[info.gitdir] = repo_cache[info.gitdir] or M._new(info)
    return repo_cache[info.gitdir]
  end)
end

--- @async
--- @param gitdir string
--- @param head_str string
--- @param cwd string
--- @return string
local function process_abbrev_head(gitdir, head_str, cwd)
  if head_str ~= 'HEAD' then
    return head_str
  end

  local short_sha = git_command({ 'rev-parse', '--short', 'HEAD' }, {
    ignore_error = true,
    cwd = cwd,
  })[1] or ''

  -- Make tests easier
  if short_sha ~= '' and log.debug_mode() then
    short_sha = 'HEAD'
  end

  if is_rebasing(gitdir) then
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
