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
--- @param args string[]
--- @param spec? Gitsigns.Git.JobSpec
--- @return string[] stdout
--- @return string? stderr
--- @return integer code
function M:command(args, spec)
  spec = spec or {}
  spec.cwd = self.toplevel

  local args1 = { '--git-dir', self.gitdir }

  if self.detached then
    vim.list_extend(args1, { '--work-tree', self.toplevel })
  end

  vim.list_extend(args1, args)

  return git_command(args1, spec)
end

--- @param base string?
--- @return string[]
function M:files_changed(base)
  --- @type string[]
  local results
  if base and base ~= ':0' then
    results = self:command({ 'diff', '--name-status', base })

    for i, result in ipairs(results) do
      results[i] = vim.split(string.gsub(result, '\t', ' '), ' ', { plain = true })[2]
    end
    return results
  else
    results = self:command({ 'status', '--porcelain', '--ignore-submodules' })

    local ret = {} --- @type string[]
    for _, line in ipairs(results) do
      if line:sub(1, 2):match('^.M') then
        ret[#ret + 1] = line:sub(4, -1)
      end
    end
    return ret
  end
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
    local refcount = repo_cache[gitdir][1]
    repo_cache[gitdir][1] = refcount + 1
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
--- @param toplevel? string
--- @return Gitsigns.RepoInfo? info, string? err
function M.get_info(cwd, gitdir, toplevel)
  -- Does git rev-parse have --absolute-git-dir, added in 2.13:
  --    https://public-inbox.org/git/20170203024829.8071-16-szeder.dev@gmail.com/
  local has_abs_gd = check_version({ 2, 13 })

  -- Wait for internal scheduler to settle before running command (#215)
  async.scheduler()

  local args = {}

  if gitdir then
    vim.list_extend(args, { '--git-dir', gitdir })
  end

  if toplevel then
    vim.list_extend(args, { '--work-tree', toplevel })
  end

  vim.list_extend(args, {
    'rev-parse',
    '--show-toplevel',
    has_abs_gd and '--absolute-git-dir' or '--git-dir',
    '--abbrev-ref',
    'HEAD',
  })

  local stdout, stderr, code = git_command(args, {
    ignore_error = true,
    cwd = toplevel or cwd,
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

  return {
    toplevel = toplevel_r,
    gitdir = gitdir_r,
    abbrev_head = process_abbrev_head(gitdir_r, assert(stdout[3]), cwd),
    detached = toplevel_r and gitdir_r ~= toplevel_r .. '/.git',
  }
end

return M
