local wrap = require('plenary.async.async').wrap
local scheduler = require('plenary.async.util').scheduler
local JobSpec = require('plenary.job').JobSpec

local gsd = require("gitsigns.debug")
local util = require('gitsigns.util')

local gs_hunks = require("gitsigns.hunks")
local Hunk = gs_hunks.Hunk

local uv = vim.loop
local startswith = vim.startswith

local record GJobSpec
  command: string
  args: {string}
  cwd: string
  on_stdout: function
  on_stderr: function
  on_exit: function
  writer: {string}

  -- gitsigns extensions
  supress_stderr: boolean
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
  command    : function(args: {string}, spec: GJobSpec): {string}, string

  record Obj
    toplevel      : string
    gitdir        : string
    file          : string
    abbrev_head   : string
    username      : string
    relpath       : string
    orig_relpath  : string -- Use for tracking moved files
    object_name   : string
    mode_bits     : string
    has_conflicts : boolean

    command              : function(Obj, {string}, GJobSpec): {string}, string
    update_abbrev_head   : function(Obj)
    update_file_info     : function(Obj): boolean
    unstage_file         : function(Obj, string, string)
    get_show_text        : function(Obj, string): {string}, string
    run_blame            : function(Obj, {string}, number): M.BlameInfo
    file_info            : function(Obj, string): string, string, string, boolean
    ensure_file_in_index : function(Obj)
    stage_hunks          : function(Obj, {Hunk}, boolean)
    has_moved            : function(Obj): string
    files_changed        : function(Obj): {string}
    new                  : function(string): Obj
  end

end

local Obj = M.Obj

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

M.command = wrap(function(args: {string}, spec: GJobSpec, callback: function({string}, string))
  local result: {string} = {}
  local reserr: string
  spec = spec or {}
  spec.command = spec.command or 'git'
  spec.args = {'--no-pager', unpack(args) }
  spec.on_stdout = spec.on_stdout or function(_, line: string)
    table.insert(result, line)
  end
  spec.on_stderr = spec.on_stderr or function(err: string, line: string)
    if not spec.supress_stderr then
      if err  then gsd.eprint(err)  end
      if line then gsd.eprint(line) end
    end
    if not reserr then
      reserr = ''
    else
      reserr = reserr..'\n'
    end
    if err  then reserr = reserr..err  end
    if line then reserr = reserr..line end
  end
  local old_on_exit = spec.on_exit
  spec.on_exit = function()
    if old_on_exit then
      old_on_exit()
    end
    callback(result, reserr)
  end
  util.run_job(spec as JobSpec)
end, 3)

local function process_abbrev_head(gitdir: string, head_str: string): string
  if not gitdir then
    return head_str
  end
  if head_str == 'HEAD' then
    if util.path_exists(gitdir..'/rebase-merge')
      or util.path_exists(gitdir..'/rebase-apply') then
      return '(rebasing)'
    elseif gsd.debug_mode then
      return head_str
    else
      return ''
    end
  end
  return head_str
end

local get_repo_info = function(path: string, cmd: string): string,string,string
  -- Does git rev-parse have --absolute-git-dir, added in 2.13:
  --   https://public-inbox.org/git/20170203024829.8071-16-szeder.dev@gmail.com/
  local has_abs_gd = check_version{2,13}
  local git_dir_opt = has_abs_gd and '--absolute-git-dir' or '--git-dir'

  -- Wait for internal scheduler to settle before running command
  --   https://github.com/lewis6991/gitsigns.nvim/pull/215
  scheduler()

  local results = M.command({
    'rev-parse', '--show-toplevel', git_dir_opt, '--abbrev-ref', 'HEAD',
  }, {
    command = cmd or 'git',
    supress_stderr = true,
    cwd = path
  })

  local toplevel = results[1]
  local gitdir = results[2]
  if not has_abs_gd then
    gitdir = uv.fs_realpath(gitdir)
  end
  local abbrev_head = process_abbrev_head(gitdir, results[3])
  return toplevel, gitdir, abbrev_head
end

M.set_version = function(version: string)
  if version ~= 'auto' then
    M.version = parse_version(version)
    return
  end
  local results = M.command{'--version'}
  local line = results[1]
  assert(startswith(line, 'git version'), 'Unexpected output: '..line)
  local parts = vim.split(line, '%s+')
  M.version = parse_version(parts[3])
end

--------------------------------------------------------------------------------
-- Git object methods
--------------------------------------------------------------------------------

--- Run git command the with the objects gitdir and toplevel
Obj.command = function(self: Obj, args: {string}, spec: GJobSpec): {string}, string
  spec = spec or {}
  spec.cwd = self.toplevel
  return M.command({'--git-dir='..self.gitdir, unpack(args)}, spec)
end

Obj.update_abbrev_head = function(self: Obj)
  _, _, self.abbrev_head = get_repo_info(self.toplevel)
end

Obj.update_file_info = function(self: Obj): boolean
  local old_object_name = self.object_name
  _, self.object_name, self.mode_bits, self.has_conflicts = self:file_info()

  return old_object_name ~= self.object_name
end

Obj.file_info = function(self: Obj, file: string): string, string, string, boolean
  local results = self:command({
    'ls-files',
    '--stage',
    '--others',
    '--exclude-standard',
    file or self.file
  })

  local relpath: string
  local object_name: string
  local mode_bits: string
  local stage: number
  local has_conflict: boolean = false
  for _, line in ipairs(results) do
    local parts = vim.split(line, '\t')
    if #parts > 1 then -- tracked file
      relpath = parts[2]
      local attrs = vim.split(parts[1], '%s+')
      stage = tonumber(attrs[3])
      if stage <= 1 then
          mode_bits   = attrs[1]
          object_name = attrs[2]
      else
          has_conflict = true
      end
    else -- untracked file
      relpath = parts[1]
    end
  end
  return relpath, object_name, mode_bits, has_conflict
end

Obj.unstage_file = function(self: Obj)
  self:command{'reset', self.file }
end

--- Get version of file in the index, return array lines
Obj.get_show_text = function(self: Obj, object: string): {string}, string
  return self:command({'show', object}, {
    supress_stderr = true
  })
end

Obj.run_blame = function(self: Obj, lines: {string}, lnum: number): M.BlameInfo
  if not self.object_name then
    -- As we support attaching to untracked files we need to return something if
    -- the file isn't isn't tracked in git.
    return {
      author             = 'Not Committed Yet',
      ['author-mail']    = '<not.committed.yet>',
      committer          = 'Not Committed Yet',
      ['committer-mail'] = '<not.committed.yet>',
    }
  end
  local results = self:command({
      'blame',
      '--contents', '-',
      '-L', lnum..',+1',
      '--line-porcelain',
      self.file
    }, {
    writer = lines,
  })
  if #results == 0 then
    return {}
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
    end
  end
  return ret as M.BlameInfo
end

Obj.ensure_file_in_index = function(self: Obj)
  if not self.object_name or self.has_conflicts then
    if not self.object_name then
      -- If there is no object_name then it is not yet in the index so add it
      self:command{'add', '--intent-to-add', self.file}
    else
      -- Update the index with the common ancestor (stage 1) which is what bcache
      -- stores
      local info = table.concat({self.mode_bits, self.object_name, self.relpath}, ',')
      self:command{'update-index', '--add', '--cacheinfo', info}
    end

    -- Update file info
    _, self.object_name, self.mode_bits, self.has_conflicts = self:file_info()
  end
end

Obj.stage_hunks = function(self: Obj, hunks: {Hunk}, invert: boolean)
  self:ensure_file_in_index()
  self:command({
    'apply', '--whitespace=nowarn', '--cached', '--unidiff-zero', '-'
  }, {
    writer = gs_hunks.create_patch(self.relpath, hunks, self.mode_bits, invert)
  })
end

Obj.has_moved = function(self: Obj): string
  local out = self:command{'diff', '--name-status', '-C', '--cached'}
  local orig_relpath = self.orig_relpath or self.relpath
  for _, l in ipairs(out) do
    local parts = vim.split(l, '%s+')
    if #parts == 3 then
      local orig, new = parts[2], parts[3]
      if orig_relpath == orig then
        self.orig_relpath = orig_relpath
        self.relpath = new
        self.file = self.toplevel..'/'..new
        return new
      end
    end
  end
end

Obj.files_changed = function(self: Obj): {string}
  local ret: {string} = {}
  self:command({'status', '--porcelain'}, {
    on_stdout = function(_, line: string)
      if line:sub(1, 2):match('^.M') then
        ret[#ret+1] = line:sub(4, -1)
      end
    end
  })
  return ret
end

Obj.new = function(file: string): Obj
  local self = setmetatable({} as Obj, {__index = Obj})

  self.file = file
  self.username = M.command({'config', 'user.name'})[1]
  self.toplevel, self.gitdir, self.abbrev_head =
    get_repo_info(util.dirname(file))

  -- Try yadm
  if M.enable_yadm and not self.gitdir then
    if vim.startswith(file, os.getenv('HOME'))
      and #M.command({'ls-files', file}, {command = 'yadm'}) ~= 0 then
      self.toplevel, self.gitdir, self.abbrev_head =
        get_repo_info(util.dirname(file), 'yadm')
    end
  end

  if not self.gitdir then
    return self
  end

  self.relpath, self.object_name, self.mode_bits, self.has_conflicts =
    self:file_info()

  return self
end

return M
