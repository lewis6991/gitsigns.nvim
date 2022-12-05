local async = require('gitsigns.async')
local scheduler = require('gitsigns.async').scheduler

local gsd = require("gitsigns.debug")
local util = require('gitsigns.util')
local subprocess = require('gitsigns.subprocess')

local gs_hunks = require("gitsigns.hunks")
local Hunk = gs_hunks.Hunk

local uv = vim.loop
local startswith = vim.startswith

local dprint = require("gitsigns.debug").dprint
local eprint = require("gitsigns.debug").eprint
local err = require('gitsigns.message').error

local record GJobSpec
  command: string
  args: {string}
  cwd: string
  writer: {string}

  -- local extensions
  suppress_stderr: boolean
end

local record M
  record BlameInfo
    -- Info in header
    sha: string
    abbrev_sha: string
    orig_lnum: integer
    final_lnum: integer

    -- Porcelain fields
    author: string
    author_mail: string
    author_time: integer
    author_tz: string
    committer: string
    committer_mail: string
    committer_time: integer
    committer_tz: string
    summary: string
    previous: string
    previous_filename: string
    previous_sha: string
    filename: string
  end

  record Version
    major: integer
    minor: integer
    patch: integer
  end
  version: Version

  enable_yadm: boolean

  set_version: function(string)

  record RepoInfo
    gitdir: string
    toplevel: string
    detached: boolean
    abbrev_head: string
  end

  get_repo_info: function(path: string, cmd: string, gitdir: string, toplevel: string): RepoInfo

  diff: function(file_cmp: string, file_buf: string, indent_heuristic: boolean, diff_algo: string): {string}, string

  record Repo
    toplevel   : string
    gitdir     : string
    detached   : boolean
    abbrev_head: string
    username   : string

    command            : function(Repo, {string}, GJobSpec): {string}, string
    files_changed      : function(Repo): {string}
    get_show_text      : function(Repo, string, string): {string}, string
    update_abbrev_head : function(Repo)
    new                : function(dir: string, gitdir: string, toplevel: string): Repo
  end

  record FileProps
    relpath       : string
    orig_relpath  : string -- Use for tracking moved files
    object_name   : string
    mode_bits     : string
    has_conflicts : boolean
    i_crlf        : boolean  -- Object has crlf
    w_crlf        : boolean  -- Working copy has crlf
  end

  record Obj
    repo          : Repo
    file          : string
    relpath       : string
    orig_relpath  : string -- Use for tracking moved files
    object_name   : string
    mode_bits     : string
    has_conflicts : boolean
    i_crlf        : boolean  -- Object has crlf
    w_crlf        : boolean  -- Working copy has crlf
    encoding      : string

    command              : function(Obj, {string}, GJobSpec): {string}, string
    update_file_info     : function(Obj, boolean, silent: boolean): boolean
    unstage_file         : function(Obj, string, string)
    run_blame            : function(Obj, {string}, number, boolean): BlameInfo
    file_info            : function(Obj, string, silent: boolean): FileProps
    get_show_text        : function(Obj, string): {string}, string
    ensure_file_in_index : function(Obj)
    stage_hunks          : function(Obj, {Hunk}, boolean)
    stage_lines          : function(Obj, {string})
    has_moved            : function(Obj): string
    new                  : function(path: string, enc: string, gitdir: string, toplevel: string): Obj
  end

end

local in_git_dir = function(file: string): boolean
  for _, p in ipairs(vim.split(file, util.path_sep)) do
    if p == '.git' then
      return true
    end
  end
  return false
end

local Obj = M.Obj
local Repo = M.Repo

local function parse_version(version: string): M.Version
  assert(version:match('%d+%.%d+%.%w+'), 'Invalid git version: '..version)
  local ret: M.Version = {}
  local parts = vim.split(version, '%.')
  ret.major = tonumber(parts[1]) as integer
  ret.minor = tonumber(parts[2]) as integer

  if parts[3] == 'GIT' then
    ret.patch = 0
  else
    ret.patch = tonumber(parts[3]) as integer
  end

  return ret
end

-- Usage: check_version{2,3}
local function check_version(version: {number,number,number}): boolean
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

local git_command = async.create(function(args: {string}, spec: GJobSpec): {string}, string
  spec = spec or {}
  spec.command = spec.command or 'git'
  spec.args = spec.command == 'git' and {
    '--no-pager',
    '--literal-pathspecs',
    '-c', 'gc.auto=0',  -- Disable auto-packing which emits messages to stderr
    unpack(args)
  } or args

  if not spec.cwd and not uv.cwd() then
    spec.cwd = vim.env.HOME
  end

  local _, _, stdout, stderr = async.wait(2, subprocess.run_job, spec as subprocess.JobSpec)

  if not spec.suppress_stderr then
    if stderr then
      local cmd_str = table.concat({spec.command, unpack(args)}, ' ')
      gsd.eprintf("Recieved stderr when running command\n'%s':\n%s", cmd_str, stderr)
    end
  end

  local stdout_lines = vim.split(stdout or '', '\n', true)

  -- If stdout ends with a newline, then remove the final empty string after
  -- the split
  if stdout_lines[#stdout_lines] == '' then
    stdout_lines[#stdout_lines] = nil
  end

  if gsd.verbose then
    gsd.vprintf('%d lines:', #stdout_lines)
    for i = 1, math.min(10, #stdout_lines) do
      gsd.vprintf('\t%s', stdout_lines[i])
    end
  end

  return stdout_lines, stderr
end, 2)

function M.diff(file_cmp: string, file_buf: string, indent_heuristic: boolean, diff_algo: string): {string}, string
  return git_command{
    '-c', 'core.safecrlf=false',
    'diff',
    '--color=never',
    '--'..(indent_heuristic and '' or 'no-')..'indent-heuristic',
    '--diff-algorithm='..diff_algo,
    '--patch-with-raw',
    '--unified=0',
    file_cmp,
    file_buf,
  }
end

local function process_abbrev_head(gitdir: string, head_str: string, path: string, cmd: string): string
  if not gitdir then
    return head_str
  end
  if head_str == 'HEAD' then
    local short_sha = git_command({'rev-parse', '--short', 'HEAD'}, {
        command = cmd or 'git',
        suppress_stderr = true,
        cwd = path,
      })[1] or ''
    if gsd.debug_mode and short_sha ~= '' then
      short_sha = 'HEAD'
    end
    if util.path_exists(gitdir..'/rebase-merge')
      or util.path_exists(gitdir..'/rebase-apply') then
      return short_sha..'(rebasing)'
    end
    return short_sha
  end
  return head_str
end

local has_cygpath = jit and jit.os == 'Windows' and vim.fn.executable('cygpath') == 1

local cygpath_convert: function(path: string): string

if has_cygpath then
  cygpath_convert = function(path: string): string
    return git_command({ '-aw', path }, { command = 'cygpath' })[1]
  end
end

local function normalize_path(path: string): string
  if path and has_cygpath and not uv.fs_stat(path) then
    -- If on windows and path isn't recognizable as a file, try passing it
    -- through cygpath
    path = cygpath_convert(path)
  end
  return path
end

function M.get_repo_info(path: string, cmd: string, gitdir: string, toplevel: string): M.RepoInfo
  -- Does git rev-parse have --absolute-git-dir, added in 2.13:
  --   https://public-inbox.org/git/20170203024829.8071-16-szeder.dev@gmail.com/
  local has_abs_gd = check_version{2,13}
  local git_dir_opt = has_abs_gd and '--absolute-git-dir' or '--git-dir'

  -- Wait for internal scheduler to settle before running command
  --   https://github.com/lewis6991/gitsigns.nvim/pull/215
  scheduler()

  local args = {}

  if gitdir then
    vim.list_extend(args, {'--git-dir', gitdir})
  end

  if toplevel then
    vim.list_extend(args, {'--work-tree', toplevel})
  end

  vim.list_extend(args, {
    'rev-parse', '--show-toplevel', git_dir_opt, '--abbrev-ref', 'HEAD',
  })

  local results = git_command(args, {
    command = cmd or 'git',
    suppress_stderr = true,
    cwd = toplevel or path,
  })

  local ret: M.RepoInfo = {
    toplevel = normalize_path(results[1]),
    gitdir = normalize_path(results[2]),
  }
  ret.abbrev_head = process_abbrev_head(ret.gitdir, results[3], path, cmd)
  if ret.gitdir and not has_abs_gd then
    ret.gitdir = uv.fs_realpath(ret.gitdir)
  end
  ret.detached = ret.toplevel and ret.gitdir ~= ret.toplevel..'/.git'
  return ret
end

function M.set_version(version: string)
  if version ~= 'auto' then
    M.version = parse_version(version)
    return
  end
  local results, stderr = git_command{'--version'}
  local line = results[1]
  if not line then
    err("Unable to detect git version as 'git --version' failed to return anything")
    eprint(stderr)
    return
  end
  assert(type(line) == 'string', 'Unexpected output: '..line)
  assert(startswith(line, 'git version'), 'Unexpected output: '..line)
  local parts = vim.split(line, '%s+')
  M.version = parse_version(parts[3])
end

--------------------------------------------------------------------------------
-- Git repo object methods
--------------------------------------------------------------------------------

--- Run git command the with the objects gitdir and toplevel
function Repo:command(args: {string}, spec: GJobSpec): {string}, string
  spec = spec or {}
  spec.cwd = self.toplevel

  local args1 = {
    '--git-dir', self.gitdir,
  }

  if self.detached then
    vim.list_extend(args1, {'--work-tree', self.toplevel})
  end

  vim.list_extend(args1, args)

  return git_command(args1, spec)
end

function Repo:files_changed(): {string}
  local results = self:command({ 'status', '--porcelain', '--ignore-submodules' })

  local ret: {string} = {}
  for _, line in ipairs(results) do
    if line:sub(1, 2):match('^.M') then
      ret[#ret+1] = line:sub(4, -1)
    end
  end
  return ret
end

local function make_bom(...: integer): string
  local r = {}
  for i, a in ipairs{...} do
    r[i] = string.char(a)
  end
  return table.concat(r)
end

local BOM_TABLE: {string:string} = {
  ['utf-8']    = make_bom(0xef, 0xbb, 0xbf),
  ['utf-16le'] = make_bom(0xff, 0xfe),
  ['utf-16']   = make_bom(0xfe, 0xff),
  ['utf-16be'] = make_bom(0xfe, 0xff),
  ['utf-32le'] = make_bom(0xff, 0xfe, 0x00, 0x00),
  ['utf-32']   = make_bom(0xff, 0xfe, 0x00, 0x00),
  ['utf-32be'] = make_bom(0x00, 0x00, 0xfe, 0xff),
  ['utf-7']    = make_bom(0x2b, 0x2f, 0x76),
  ['utf-1']    = make_bom(0xf7, 0x54, 0x4c),
}

local function strip_bom(x: string, encoding: string): string
 local bom = BOM_TABLE[encoding]
 if bom and vim.startswith(x, bom) then
   return x:sub(bom:len() + 1)
 end
 return x
end

local function iconv_supported(encoding: string): boolean
  -- TODO(lewis6991): needs https://github.com/neovim/neovim/pull/21924
  if vim.startswith(encoding, 'utf-16') then
    return false
  elseif vim.startswith(encoding, 'utf-32') then
    return false
  end
  return true
end

--- Get version of file in the index, return array lines
function Repo:get_show_text(object: string, encoding: string): {string}, string
  local stdout, stderr = self:command({'show', object}, {suppress_stderr = true})

  if encoding and encoding ~= 'utf-8' and iconv_supported(encoding) then
    stdout[1] = strip_bom(stdout[1], encoding)
    if vim.iconv then
      for i, l in ipairs(stdout) do
        stdout[i] = vim.iconv(l, encoding, 'utf-8')
      end
    else
      scheduler()
      for i, l in ipairs(stdout) do
        -- vimscript will interpret strings containing NUL as blob type
        if vim.fn.type(l) == vim.v.t_string then
          stdout[i] = vim.fn.iconv(l, encoding, 'utf-8')
        end
      end
    end
  end

  return stdout, stderr
end

function Repo:update_abbrev_head()
  self.abbrev_head = M.get_repo_info(self.toplevel).abbrev_head
end

function Repo.new(dir: string, gitdir: string, toplevel: string): Repo
  local self: Repo = setmetatable({}, {__index = Repo})

  self.username = git_command({'config', 'user.name'})[1]
  local info = M.get_repo_info(dir, nil, gitdir, toplevel)
  for k, v in pairs(info as table) do
    (self as table)[k] = v
  end

  -- Try yadm
  if M.enable_yadm and not self.gitdir then
    if vim.startswith(dir, os.getenv('HOME'))
      and #git_command({'ls-files', dir}, {command = 'yadm'}) ~= 0 then
      M.get_repo_info(dir, 'yadm', gitdir, toplevel)
      local yadm_info = M.get_repo_info(dir, 'yadm', gitdir, toplevel)
      for k, v in pairs(yadm_info as {string:any}) do
        (self as table)[k] = v
      end
    end
  end

  return self
end

--------------------------------------------------------------------------------
-- Git object methods
--------------------------------------------------------------------------------

--- Run git command the with the objects gitdir and toplevel
function Obj:command(args: {string}, spec: GJobSpec): {string}, string
  return self.repo:command(args, spec)
end

function Obj:update_file_info(update_relpath: boolean, silent: boolean): boolean
  local old_object_name = self.object_name
  local props = self:file_info(self.file, silent)

  if update_relpath then
    self.relpath = props.relpath
  end
  self.object_name   = props.object_name
  self.mode_bits     = props.mode_bits
  self.has_conflicts = props.has_conflicts
  self.i_crlf        = props.i_crlf
  self.w_crlf        = props.w_crlf

  return old_object_name ~= self.object_name
end

function Obj:file_info(file: string, silent: boolean): M.FileProps
  local results, stderr = self:command({
    '-c', 'core.quotepath=off',
    'ls-files',
    '--stage',
    '--others',
    '--exclude-standard',
    '--eol',
    file or self.file
  }, {suppress_stderr = true})

  if stderr and not silent then
    -- Suppress_stderr for the cases when we run:
    --   git ls-files --others exists/nonexist
    if not stderr:match('^warning: could not open directory .*: No such file or directory') then
      gsd.eprint(stderr)
    end
  end

  local result: M.FileProps = {}
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
          result.mode_bits   = attrs[1]
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

function Obj:get_show_text(revision: string): {string}, string
  if not self.relpath then
    return {}
  end

  local stdout, stderr =  self.repo:get_show_text(revision..':'..self.relpath, self.encoding)

  if not self.i_crlf and self.w_crlf then
    -- Add cr
    for i = 1, #stdout do
      stdout[i] = stdout[i]..'\r'
    end
  end

  return stdout, stderr
end

Obj.unstage_file = function(self: Obj)
  self:command{'reset', self.file }
end

function Obj:run_blame(lines: {string}, lnum: number, ignore_whitespace: boolean): M.BlameInfo
  if not self.object_name or self.repo.abbrev_head == '' then
    -- As we support attaching to untracked files we need to return something if
    -- the file isn't isn't tracked in git.
    -- If abbrev_head is empty, then assume the repo has no commits
    return {
      author             = 'Not Committed Yet',
      ['author_mail']    = '<not.committed.yet>',
      committer          = 'Not Committed Yet',
      ['committer_mail'] = '<not.committed.yet>',
    }
  end

  local args = {
    'blame',
    '--contents', '-',
    '-L', lnum..',+1',
    '--line-porcelain',
    self.file
  }

  if ignore_whitespace then
    args[#args+1] = '-w'
  end

  local ignore_file = self.repo.toplevel ..'/.git-blame-ignore-revs'
  if uv.fs_stat(ignore_file) then
    vim.list_extend(args, {'--ignore-revs-file', ignore_file})
  end

  local results = self:command(args, { writer = lines })
  if #results == 0 then
    return
  end
  local header = vim.split(table.remove(results, 1), ' ')

  local ret: {string:any} = {}
  ret.sha = header[1]
  ret.orig_lnum = tonumber(header[2]) as integer
  ret.final_lnum = tonumber(header[3]) as integer
  ret.abbrev_sha = string.sub(ret.sha as string, 1, 8)
  for _, l in ipairs(results) do
    if not startswith(l, '\t') then
      local cols = vim.split(l, ' ')
      local key = table.remove(cols, 1):gsub('-', '_')
      ret[key] = table.concat(cols, ' ')
      if key == 'previous' then
        ret.previous_sha = cols[1]
        ret.previous_filename = cols[2]
      end
    end
  end
  return ret as M.BlameInfo
end

local function ensure_file_in_index(obj: Obj)
  if obj.object_name and not obj.has_conflicts then
    return
  end

  if not obj.object_name then
    -- If there is no object_name then it is not yet in the index so add it
    obj:command{'add', '--intent-to-add', obj.file}
  else
    -- Update the index with the common ancestor (stage 1) which is what bcache
    -- stores
    local info = string.format('%s,%s,%s', obj.mode_bits, obj.object_name, obj.relpath)
    obj:command{'update-index', '--add', '--cacheinfo', info}
  end

  obj:update_file_info()
end

-- Stage 'lines' as the entire contents of the file
--- @param lines
function Obj:stage_lines(lines: {string})
  local stdout = self:command({
    'hash-object', '-w', '--path', self.relpath, '--stdin'
  }, { writer = lines })

  local new_object = stdout[1]

  self:command{
    'update-index', '--cacheinfo', string.format('%s,%s,%s', self.mode_bits, new_object, self.relpath)
  }
end

Obj.stage_hunks = function(self: Obj, hunks: {Hunk}, invert: boolean)
  ensure_file_in_index(self)
  self:command({
    'apply', '--whitespace=nowarn', '--cached', '--unidiff-zero', '-'
  }, {
    writer = gs_hunks.create_patch(self.relpath, hunks, self.mode_bits, invert)
  })
end

function Obj:has_moved(): string
  local out = self:command{'diff', '--name-status', '-C', '--cached'}
  local orig_relpath = self.orig_relpath or self.relpath
  for _, l in ipairs(out) do
    local parts = vim.split(l, '%s+')
    if #parts == 3 then
      local orig, new = parts[2], parts[3]
      if orig_relpath == orig then
        self.orig_relpath = orig_relpath
        self.relpath = new
        self.file = self.repo.toplevel..'/'..new
        return new
      end
    end
  end
end

function Obj.new(file: string, encoding: string, gitdir: string, toplevel: string): Obj
  if in_git_dir(file) then
      dprint('In git dir')
      return nil
  end
  local self: Obj = setmetatable({}, {__index = Obj})

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
