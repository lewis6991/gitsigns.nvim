local async = require('gitsigns.async')
local scheduler = require('gitsigns.async').scheduler

local log = require('gitsigns.debug.log')
local util = require('gitsigns.util')
local subprocess = require('gitsigns.subprocess')

local gs_config = require('gitsigns.config')
local config = gs_config.config

local gs_hunks = require('gitsigns.hunks')

local uv = vim.loop
local startswith = vim.startswith

local dprint = require('gitsigns.debug.log').dprint
local eprint = require('gitsigns.debug.log').eprint
local err = require('gitsigns.message').error

local M = {}

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
--- @field object_name string
--- @field relpath string
--- @field orig_relpath? string Use for tracking moved files
--- @field repo Gitsigns.Repo
--- @field has_conflicts? boolean
local Obj = {}

M.Obj = Obj

--- @class Gitsigns.Repo
--- @field gitdir string
--- @field toplevel string
--- @field detached boolean
--- @field abbrev_head string
--- @field username string
local Repo = {}
M.Repo = Repo

--- @class Gitsigns.Version
--- @field major integer
--- @field minor integer
--- @field patch integer

--- @param version string
--- @return Gitsigns.Version
local function parse_version(version)
  assert(version:match('%d+%.%d+%.%w+'), 'Invalid git version: ' .. version)
  local ret = {}
  local parts = vim.split(version, '%.')
  ret.major = assert(tonumber(parts[1]))
  ret.minor = assert(tonumber(parts[2]))

  if parts[3] == 'GIT' then
    ret.patch = 0
  else
    ret.patch = assert(tonumber(parts[3]))
  end

  return ret
end

-- Usage: check_version{2,3}
--- @param version {[1]: integer, [2]:integer, [3]:integer}
--- @return boolean
local function check_version(version)
  if not M.version then
    return false
  end
  if M.version.major < version[1] then
    return false
  end
  if version[2] and M.version.minor < version[2] then
    return false
  end
  if version[3] and M.version.patch < version[3] then
    return false
  end
  return true
end

--- @param version string
function M._set_version(version)
  if version ~= 'auto' then
    M.version = parse_version(version)
    return
  end

  --- @type integer, integer, string?, string?
  local _, _, stdout, stderr = async.wait(2, subprocess.run_job, {
    command = 'git',
    args = { '--version' },
  })

  local line = vim.split(stdout or '', '\n', { plain = true })[1]
  if not line then
    err("Unable to detect git version as 'git --version' failed to return anything")
    eprint(stderr)
    return
  end
  assert(type(line) == 'string', 'Unexpected output: ' .. line)
  assert(startswith(line, 'git version'), 'Unexpected output: ' .. line)
  local parts = vim.split(line, '%s+')
  M.version = parse_version(parts[3])
end

--- @param args string[]
--- @param spec? Gitsigns.JobSpec
--- @return string[] stdout, string? stderr
local git_command = async.create(function(args, spec)
  if not M.version then
    M._set_version(config._git_version)
  end
  spec = spec or {}
  spec.command = spec.command or 'git'
  spec.args = spec.command == 'git'
      and {
        '--no-pager',
        '--literal-pathspecs',
        '-c',
        'gc.auto=0', -- Disable auto-packing which emits messages to stderr
        unpack(args),
      }
    or args

  if not spec.cwd and not uv.cwd() then
    spec.cwd = vim.env.HOME
  end

  --- @type integer, integer, string?, string?
  local _, _, stdout, stderr = async.wait(2, subprocess.run_job, spec)

  if not spec.suppress_stderr then
    if stderr then
      local cmd_str = table.concat({ spec.command, unpack(args) }, ' ')
      log.eprintf("Received stderr when running command\n'%s':\n%s", cmd_str, stderr)
    end
  end

  local stdout_lines = vim.split(stdout or '', '\n', { plain = true })

  -- If stdout ends with a newline, then remove the final empty string after
  -- the split
  if stdout_lines[#stdout_lines] == '' then
    stdout_lines[#stdout_lines] = nil
  end

  if log.verbose then
    log.vprintf('%d lines:', #stdout_lines)
    for i = 1, math.min(10, #stdout_lines) do
      log.vprintf('\t%s', stdout_lines[i])
    end
  end

  return stdout_lines, stderr
end, 2)

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
  })
end

--- @param gitdir string
--- @param head_str string
--- @param path string
--- @param cmd? string
--- @return string
local function process_abbrev_head(gitdir, head_str, path, cmd)
  if not gitdir then
    return head_str
  end
  if head_str == 'HEAD' then
    local short_sha = git_command({ 'rev-parse', '--short', 'HEAD' }, {
      command = cmd or 'git',
      suppress_stderr = true,
      cwd = path,
    })[1] or ''
    if log.debug_mode and short_sha ~= '' then
      short_sha = 'HEAD'
    end
    if
      util.path_exists(gitdir .. '/rebase-merge')
      or util.path_exists(gitdir .. '/rebase-apply')
    then
      return short_sha .. '(rebasing)'
    end
    return short_sha
  end
  return head_str
end

local has_cygpath = jit and jit.os == 'Windows' and vim.fn.executable('cygpath') == 1

local cygpath_convert ---@type fun(path: string): string

if has_cygpath then
  cygpath_convert = function(path)
    return git_command({ '-aw', path }, { command = 'cygpath' })[1]
  end
end

--- @param path string
--- @return string
local function normalize_path(path)
  if path and has_cygpath and not uv.fs_stat(path) then
    -- If on windows and path isn't recognizable as a file, try passing it
    -- through cygpath
    path = cygpath_convert(path)
  end
  return path
end

--- @class Gitsigns.RepoInfo
--- @field gitdir string
--- @field toplevel string
--- @field detached boolean
--- @field abbrev_head string

--- @param path string
--- @param cmd? string
--- @param gitdir? string
--- @param toplevel? string
--- @return Gitsigns.RepoInfo
function M.get_repo_info(path, cmd, gitdir, toplevel)
  -- Does git rev-parse have --absolute-git-dir, added in 2.13:
  --    https://public-inbox.org/git/20170203024829.8071-16-szeder.dev@gmail.com/
  local has_abs_gd = check_version({ 2, 13 })
  local git_dir_opt = has_abs_gd and '--absolute-git-dir' or '--git-dir'

  -- Wait for internal scheduler to settle before running command
  --    https://github.com/lewis6991/gitsigns.nvim/pull/215
  scheduler()

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
    git_dir_opt,
    '--abbrev-ref',
    'HEAD',
  })

  local results = git_command(args, {
    command = cmd or 'git',
    suppress_stderr = true,
    cwd = toplevel or path,
  })

  --- @type Gitsigns.RepoInfo
  local ret = {
    toplevel = normalize_path(results[1]),
    gitdir = normalize_path(results[2]),
  }
  ret.abbrev_head = process_abbrev_head(ret.gitdir, results[3], path, cmd)
  if ret.gitdir and not has_abs_gd then
    ret.gitdir = assert(uv.fs_realpath(ret.gitdir))
  end
  ret.detached = ret.toplevel and ret.gitdir ~= ret.toplevel .. '/.git'
  return ret
end

--------------------------------------------------------------------------------
-- Git repo object methods
--------------------------------------------------------------------------------

--- Run git command the with the objects gitdir and toplevel
--- @param args string[]
--- @param spec? Gitsigns.JobSpec
--- @return string[] stdout, string? stderr
function Repo:command(args, spec)
  spec = spec or {}
  spec.cwd = self.toplevel

  local args1 = {
    '--git-dir',
    self.gitdir,
  }

  if self.detached then
    vim.list_extend(args1, { '--work-tree', self.toplevel })
  end

  vim.list_extend(args1, args)

  return git_command(args1, spec)
end

--- @return string[]
function Repo:files_changed()
  --- @type string[]
  local results = self:command({ 'status', '--porcelain', '--ignore-submodules' })

  local ret = {} --- @type string[]
  for _, line in ipairs(results) do
    if line:sub(1, 2):match('^.M') then
      ret[#ret + 1] = line:sub(4, -1)
    end
  end
  return ret
end

--- @param ... integer
--- @return string
local function make_bom(...)
  local r = {}
  ---@diagnostic disable-next-line:no-unknown
  for i, a in ipairs({ ... }) do
    ---@diagnostic disable-next-line:no-unknown
    r[i] = string.char(a)
  end
  return table.concat(r)
end

local BOM_TABLE = {
  ['utf-8'] = make_bom(0xef, 0xbb, 0xbf),
  ['utf-16le'] = make_bom(0xff, 0xfe),
  ['utf-16'] = make_bom(0xfe, 0xff),
  ['utf-16be'] = make_bom(0xfe, 0xff),
  ['utf-32le'] = make_bom(0xff, 0xfe, 0x00, 0x00),
  ['utf-32'] = make_bom(0xff, 0xfe, 0x00, 0x00),
  ['utf-32be'] = make_bom(0x00, 0x00, 0xfe, 0xff),
  ['utf-7'] = make_bom(0x2b, 0x2f, 0x76),
  ['utf-1'] = make_bom(0xf7, 0x54, 0x4c),
}

local function strip_bom(x, encoding)
  local bom = BOM_TABLE[encoding]
  if bom and vim.startswith(x, bom) then
    return x:sub(bom:len() + 1)
  end
  return x
end

--- @param encoding string
--- @return boolean
local function iconv_supported(encoding)
  -- TODO(lewis6991): needs https://github.com/neovim/neovim/pull/21924
  if vim.startswith(encoding, 'utf-16') then
    return false
  elseif vim.startswith(encoding, 'utf-32') then
    return false
  end
  return true
end

--- Get version of file in the index, return array lines
--- @param object string
--- @param encoding? string
--- @return string[] stdout, string? stderr
function Repo:get_show_text(object, encoding)
  local stdout, stderr = self:command({ 'show', object }, { suppress_stderr = true })

  if encoding and encoding ~= 'utf-8' and iconv_supported(encoding) then
    stdout[1] = strip_bom(stdout[1], encoding)
    for i, l in ipairs(stdout) do
      --- @diagnostic disable-next-line:param-type-mismatch
      stdout[i] = vim.iconv(l, encoding, 'utf-8')
    end
  end

  return stdout, stderr
end

function Repo:update_abbrev_head()
  self.abbrev_head = M.get_repo_info(self.toplevel).abbrev_head
end

--- @param dir string
--- @param gitdir? string
--- @param toplevel? string
--- @return Gitsigns.Repo
function Repo.new(dir, gitdir, toplevel)
  local self = setmetatable({}, { __index = Repo })

  self.username = git_command({ 'config', 'user.name' })[1]
  local info = M.get_repo_info(dir, nil, gitdir, toplevel)
  for k, v in
    pairs(info --[[@as table<string,any>]])
  do
    ---@diagnostic disable-next-line:no-unknown
    (self)[k] = v
  end

  -- Try yadm
  if config.yadm.enable and not self.gitdir then
    if
      vim.startswith(dir, assert(os.getenv('HOME')))
      and #git_command({ 'ls-files', dir }, { command = 'yadm' }) ~= 0
    then
      M.get_repo_info(dir, 'yadm', gitdir, toplevel)
      local yadm_info = M.get_repo_info(dir, 'yadm', gitdir, toplevel)
      for k, v in
        pairs(yadm_info --[[@as table<string,any>]])
      do
        ---@diagnostic disable-next-line:no-unknown
        (self)[k] = v
      end
    end
  end

  return self
end

--------------------------------------------------------------------------------
-- Git object methods
--------------------------------------------------------------------------------

--- Run git command the with the objects gitdir and toplevel
--- @param args string[]
--- @param spec? Gitsigns.JobSpec
--- @return string[] stdout, string? stderr
function Obj:command(args, spec)
  return self.repo:command(args, spec)
end

--- @param update_relpath? boolean
--- @param silent? boolean
--- @return boolean
function Obj:update_file_info(update_relpath, silent)
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

--- @class Gitsigns.FileInfo
--- @field relpath string
--- @field i_crlf boolean
--- @field w_crlf boolean
--- @field mode_bits string
--- @field object_name string
--- @field has_conflicts true?

--- @param file string
--- @param silent? boolean
--- @return Gitsigns.FileInfo
function Obj:file_info(file, silent)
  local results, stderr = self:command({
    '-c',
    'core.quotepath=off',
    'ls-files',
    '--stage',
    '--others',
    '--exclude-standard',
    '--eol',
    file or self.file,
  }, { suppress_stderr = true })

  if stderr and not silent then
    -- Suppress_stderr for the cases when we run:
    --    git ls-files --others exists/nonexist
    if not stderr:match('^warning: could not open directory .*: No such file or directory') then
      log.eprint(stderr)
    end
  end

  local result = {}
  for _, line in ipairs(results) do
    local parts = vim.split(line, '\t')
    if #parts > 2 then -- tracked file
      local eol = vim.split(parts[2], '%s+')
      result.i_crlf = eol[1] == 'i/crlf'
      result.w_crlf = eol[2] == 'w/crlf'
      result.relpath = parts[3]
      local attrs = vim.split(parts[1], '%s+')
      local stage = tonumber(attrs[3])
      if stage <= 1 then
        result.mode_bits = attrs[1]
        result.object_name = attrs[2]
      else
        result.has_conflicts = true
      end
    else -- untracked file
      result.relpath = parts[2]
    end
  end
  return result
end

--- @param revision string
--- @return string[] stdout, string? stderr
function Obj:get_show_text(revision)
  if not self.relpath then
    return {}
  end

  local stdout, stderr = self.repo:get_show_text(revision .. ':' .. self.relpath, self.encoding)

  if not self.i_crlf and self.w_crlf then
    -- Add cr
    for i = 1, #stdout do
      stdout[i] = stdout[i] .. '\r'
    end
  end

  return stdout, stderr
end

Obj.unstage_file = function(self)
  self:command({ 'reset', self.file })
end

--- @class Gitsigns.BlameInfo
--- -- Info in header
--- @field sha string
--- @field abbrev_sha string
--- @field orig_lnum integer
--- @field final_lnum integer
--- Porcelain fields
--- @field author string
--- @field author_mail string
--- @field author_time integer
--- @field author_tz string
--- @field committer string
--- @field committer_mail string
--- @field committer_time integer
--- @field committer_tz string
--- @field summary string
--- @field previous string
--- @field previous_filename string
--- @field previous_sha string
--- @field filename string

--- @param lines string[]
--- @param lnum integer
--- @param ignore_whitespace boolean
--- @return Gitsigns.BlameInfo?
function Obj:run_blame(lines, lnum, ignore_whitespace)
  local not_committed = {
    author = 'Not Committed Yet',
    ['author_mail'] = '<not.committed.yet>',
    committer = 'Not Committed Yet',
    ['committer_mail'] = '<not.committed.yet>',
  }

  if not self.object_name or self.repo.abbrev_head == '' then
    -- As we support attaching to untracked files we need to return something if
    -- the file isn't isn't tracked in git.
    -- If abbrev_head is empty, then assume the repo has no commits
    return not_committed
  end

  local args = {
    'blame',
    '--contents',
    '-',
    '-L',
    lnum .. ',+1',
    '--line-porcelain',
    self.file,
  }

  if ignore_whitespace then
    args[#args + 1] = '-w'
  end

  local ignore_file = self.repo.toplevel .. '/.git-blame-ignore-revs'
  if uv.fs_stat(ignore_file) then
    vim.list_extend(args, { '--ignore-revs-file', ignore_file })
  end

  local results = self:command(args, { writer = lines })
  if #results == 0 then
    return
  end
  local header = vim.split(table.remove(results, 1), ' ')

  local ret = {} --- @type Gitsigns.BlameInfo
  ret.sha = header[1]
  ret.orig_lnum = tonumber(header[2]) --[[@as integer]]
  ret.final_lnum = tonumber(header[3]) --[[@as integer]]
  ret.abbrev_sha = string.sub(ret.sha, 1, 8)
  for _, l in ipairs(results) do
    if not startswith(l, '\t') then
      local cols = vim.split(l, ' ')
      --- @type string
      local key = table.remove(cols, 1):gsub('-', '_')
      --- @diagnostic disable-next-line:no-unknown
      ret[key] = table.concat(cols, ' ')
      if key == 'previous' then
        ret.previous_sha = cols[1]
        ret.previous_filename = cols[2]
      end
    end
  end

  -- New in git 2.41:
  -- The output given by "git blame" that attributes a line to contents
  -- taken from the file specified by the "--contents" option shows it
  -- differently from a line attributed to the working tree file.
  if ret.author_mail == '<external.file>' or ret.author_mail == 'External file (--contents)' then
    ret = vim.tbl_extend('force', ret, not_committed)
  end

  return ret
end

--- @param obj Gitsigns.GitObj
local function ensure_file_in_index(obj)
  if obj.object_name and not obj.has_conflicts then
    return
  end

  if not obj.object_name then
    -- If there is no object_name then it is not yet in the index so add it
    obj:command({ 'add', '--intent-to-add', obj.file })
  else
    -- Update the index with the common ancestor (stage 1) which is what bcache
    -- stores
    local info = string.format('%s,%s,%s', obj.mode_bits, obj.object_name, obj.relpath)
    obj:command({ 'update-index', '--add', '--cacheinfo', info })
  end

  obj:update_file_info()
end

-- Stage 'lines' as the entire contents of the file
--- @param lines string[]
function Obj:stage_lines(lines)
  local stdout = self:command({
    'hash-object',
    '-w',
    '--path',
    self.relpath,
    '--stdin',
  }, { writer = lines })

  local new_object = stdout[1]

  self:command({
    'update-index',
    '--cacheinfo',
    string.format('%s,%s,%s', self.mode_bits, new_object, self.relpath),
  })
end

--- @param hunks Gitsigns.Hunk.Hunk
--- @param invert? boolean
function Obj.stage_hunks(self, hunks, invert)
  ensure_file_in_index(self)

  local patch = gs_hunks.create_patch(self.relpath, hunks, self.mode_bits, invert)

  if not self.i_crlf and self.w_crlf then
    -- Remove cr
    for i = 1, #patch do
      patch[i] = patch[i]:gsub('\r$', '')
    end
  end

  self:command({
    'apply',
    '--whitespace=nowarn',
    '--cached',
    '--unidiff-zero',
    '-',
  }, {
    writer = patch,
  })
end

--- @return string?
function Obj:has_moved()
  local out = self:command({ 'diff', '--name-status', '-C', '--cached' })
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
--- @param encoding string
--- @param gitdir string?
--- @param toplevel string?
--- @return Gitsigns.GitObj?
function Obj.new(file, encoding, gitdir, toplevel)
  if in_git_dir(file) then
    dprint('In git dir')
    return nil
  end
  local self = setmetatable({}, { __index = Obj })

  self.file = file
  self.encoding = encoding
  self.repo = Repo.new(util.dirname(file), gitdir, toplevel)

  if not self.repo.gitdir then
    dprint('Not in git repo')
    return nil
  end

  -- When passing gitdir and toplevel, suppress stderr when resolving the file
  local silent = gitdir ~= nil and toplevel ~= nil

  self:update_file_info(true, silent)

  return self
end

return M
