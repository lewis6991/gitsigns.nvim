local a = require('plenary.async_lib.async')
local JobSpec = require('plenary.job').JobSpec
local await = a.await
local async = a.async

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

  set_version: function(string): a.future0
  run_diff   : function(string, {string}, string): a.future1<{Hunk}>

  record Obj
    toplevel      : string
    gitdir        : string
    file          : string
    abbrev_head   : string
    username      : string
    relpath       : string
    object_name   : string
    mode_bits     : string
    has_conflicts : boolean

    command              : function(Obj, {string}, GJobSpec): a.future1<{string}>
    update_abbrev_head   : function(Obj): a.future0
    update_file_info     : function(Obj): a.future1<boolean>
    unstage_file         : function(Obj, string, string): a.future0
    get_show             : function(Obj, string, string): a.future0
    get_show_text        : function(Obj, string): a.future1<{string}>
    run_blame            : function(Obj, {string}, number): a.future1<M.BlameInfo>
    file_info            : function(Obj): a.future4<string, string, string, boolean>
    ensure_file_in_index : function(Obj): a.future0
    stage_hunks          : function(Obj, {Hunk}, boolean): a.future0
    new                  : function(string): a.future1<Obj>
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

local command = a.wrap(function(args: {string}, spec: GJobSpec, callback: function({string}))
  local result: {string} = {}
  spec = spec or {}
  spec.command = spec.command or 'git'
  spec.args = {'--no-pager', unpack(args) }
  spec.on_stdout = spec.on_stdout or function(_, line: string)
    table.insert(result, line)
  end
  if not spec.supress_stderr then
    spec.on_stderr = spec.on_stderr or function(err: string, line: string)
      if err  then gsd.eprint(err)  end
      if line then gsd.eprint(line) end
    end
  end
  local old_on_exit = spec.on_exit
  spec.on_exit = function()
    if old_on_exit then
      old_on_exit()
    end
    callback(result)
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

local get_repo_info = async(function(path: string, cmd: string): string,string,string
  -- Does git rev-parse have --absolute-git-dir, added in 2.13:
  --   https://public-inbox.org/git/20170203024829.8071-16-szeder.dev@gmail.com/
  local has_abs_gd = check_version{2,13}
  local git_dir_opt = has_abs_gd and '--absolute-git-dir' or '--git-dir'

  local results = await(command({
    'rev-parse', '--show-toplevel', git_dir_opt, '--abbrev-ref', 'HEAD',
  }, {
    command = cmd or 'git',
    supress_stderr = true,
    cwd = path
  }))

  local toplevel = results[1]
  local gitdir = results[2]
  if not has_abs_gd then
    gitdir = uv.fs_realpath(gitdir)
  end
  local abbrev_head = process_abbrev_head(gitdir, results[3])
  return toplevel, gitdir, abbrev_head
end)

local function write_to_file(path: string, text: {string})
  local f = io.open(path, 'wb')
  for _, l in ipairs(text) do
    f:write(l)
    f:write('\n')
  end
  f:close()
end

M.run_diff = async(function(
  staged: string,
  text: {string},
  diff_algo: string
): {Hunk}
  local results: {Hunk} = {}

  local buffile = os.tmpname()..'_buf'
  write_to_file(buffile, text)

  -- Taken from gitgutter, diff.vim:
  --
  -- If a file has CRLF line endings and git's core.autocrlf is true, the file
  -- in git's object store will have LF line endings. Writing it out via
  -- git-show will produce a file with LF line endings.
  --
  -- If this last file is one of the files passed to git-diff, git-diff will
  -- convert its line endings to CRLF before diffing -- which is what we want
  -- but also by default outputs a warning on stderr.
  --
  --   warning: LF will be replace by CRLF in <temp file>.
  --   The file will have its original line endings in your working directory.
  --
  -- We can safely ignore the warning, we turn it off by passing the '-c
  -- "core.safecrlf=false"' argument to git-diff.

  await(command({
      '-c', 'core.safecrlf=false',
      'diff',
      '--color=never',
      '--diff-algorithm='..diff_algo,
      '--patch-with-raw',
      '--unified=0',
      staged,
      buffile,
    }, {
    on_stdout = function(_, line: string)
      if startswith(line, '@@') then
        table.insert(results, gs_hunks.parse_diff_line(line))
      elseif #results > 0 then
        table.insert(results[#results].lines, line)
      end
    end
  }))
  os.remove(buffile)
  return results
end)

M.set_version = async(function(version: string)
  if version ~= 'auto' then
    M.version = parse_version(version)
    return
  end
  local results = await(command{'--version'})
  local line = results[1]
  assert(startswith(line, 'git version'), 'Unexpected output: '..line)
  local parts = vim.split(line, '%s+')
  M.version = parse_version(parts[3])
end)

--------------------------------------------------------------------------------
-- Git object methods
--------------------------------------------------------------------------------

--- Run git command the with the objects gitdir and toplevel
Obj.command = async(function(self: Obj, args: {string}, spec: GJobSpec): {string}
  spec = spec or {}
  spec.cwd = self.toplevel
  return await(command({'--git-dir='..self.gitdir, unpack(args)}, spec))
end)

Obj.update_abbrev_head = async(function(self: Obj)
  _, _, self.abbrev_head = await(get_repo_info(self.toplevel))
end)

Obj.update_file_info = async(function(self: Obj): boolean
  local old_object_name = self.object_name
  _, self.object_name, self.mode_bits, self.has_conflicts = await(self:file_info())

  return old_object_name ~= self.object_name
end)

Obj.file_info = async(function(self: Obj): string, string, string, boolean
  local results = await(self:command({
    'ls-files',
    '--stage',
    '--others',
    '--exclude-standard',
    self.file
  }))

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
end)

Obj.unstage_file = async(function(self: Obj)
    await(self:command{'reset', self.file })
end)

--- Get version of file in the index, return array lines
Obj.get_show_text = async(function(self: Obj, object: string): {string}
  return await(self:command({'show', object}, {
    supress_stderr = true
  }))
end)

--- Get version of file in the index, write lines to file
Obj.get_show = async(function(self: Obj, object: string, output_file: string)
  -- On windows 'w' mode use \r\n instead of \n, see:
  -- https://stackoverflow.com/a/43967013
  local outf = io.open(output_file, 'wb')
  await(self:command({'show', object}, {
    supress_stderr = true,
    on_stdout = function(_, line: string)
      outf:write(line)
      outf:write('\n')
    end
  }))
  outf:close()
end)

Obj.run_blame = async(function(self: Obj, lines: {string}, lnum: number): M.BlameInfo
  local results = await(self:command({
      'blame',
      '--contents', '-',
      '-L', lnum..',+1',
      '--line-porcelain',
      self.file
    }, {
    writer = lines,
  }))
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
end)

Obj.ensure_file_in_index = async(function(self: Obj)
  if not self.object_name or self.has_conflicts then
    if not self.object_name then
      -- If there is no object_name then it is not yet in the index so add it
      await(self:command{'add', '--intent-to-add', self.file})
    else
      -- Update the index with the common ancestor (stage 1) which is what bcache
      -- stores
      local info = table.concat({self.mode_bits, self.object_name, self.relpath}, ',')
      await(self:command{'update-index', '--add', '--cacheinfo', info})
    end

    -- Update file info
    _, self.object_name, self.mode_bits, self.has_conflicts = await(self:file_info())
  end
end)

Obj.stage_hunks = async(function(self: Obj, hunks: {Hunk}, invert: boolean)
  await(self:ensure_file_in_index())
  await(self:command({
    'apply', '--cached', '--unidiff-zero', '-'
  }, {
    writer = gs_hunks.create_patch(self.relpath, hunks, self.mode_bits, invert)
  }))
end)

Obj.new = a.async(function(file: string): Obj
  local self = setmetatable({} as Obj, {__index = Obj})

  self.file = file
  self.username = await(command({'config', 'user.name'}))[1]
  self.toplevel, self.gitdir, self.abbrev_head =
    await(get_repo_info(util.dirname(file)))

  -- Try yadm
  if M.enable_yadm and not self.gitdir then
    if #await(command({'ls-files', file}, {command = 'yadm'})) ~= 0 then
      self.toplevel, self.gitdir, self.abbrev_head =
        await(get_repo_info(util.dirname(file), 'yadm'))
    end
  end

  if not self.gitdir then
    return self
  end

  self.relpath, self.object_name, self.mode_bits, self.has_conflicts =
    await(self:file_info())

  return self
end)

return M
