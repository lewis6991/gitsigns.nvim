local a = require('plenary/async_lib/async')
local gsd = require("gitsigns/debug")
local util = require('gitsigns/util')

local hunks = require("gitsigns/hunks")
local Hunk = hunks.Hunk

local uv = vim.loop
local startswith = vim.startswith

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

  file_info       : function(string, string): a.future4<string, string, string, boolean>
  get_staged      : function(string, string, number, string): a.future0
  get_staged_text : function(string, string, number): a.future1<{string}>
  run_blame       : function(string, string, {string}, number, {string}): a.future1<M.BlameInfo>
  get_repo_info   : function(string): a.future3<string,string,string>
  stage_lines     : function(string, {string}): a.future0
  add_file        : function(string, string, string): a.future0
  unstage_file    : function(string, string, string): a.future0
  update_index    : function(string, string, string, string): a.future0
  run_diff        : function(string, {string}, string): a.future1<{Hunk}>
  set_version     : function(string): a.future0
  command         : function({string}): a.future1<{string}>
end

local function parse_version(version: string): M.Version
  assert(version:match('%d+%.%d+%.%d+'), 'Invalid git version: '..version)
  local ret: M.Version = {}
  local parts = vim.split(version, '%.')
  ret.major = tonumber(parts[1]) as integer
  ret.minor = tonumber(parts[2]) as integer
  ret.patch = tonumber(parts[3]) as integer
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

M.file_info = a.wrap(function(
  file: string,
  toplevel: string,
  callback: function(string, string, string, boolean)
)
  local relpath: string
  local object_name: string
  local mode_bits: string
  local stage: number
  local has_conflict: boolean = false
  util.run_job {
    command = 'git',
    args = {
      '--no-pager',
      'ls-files',
      '--stage',
      '--others',
      '--exclude-standard',
      file
    },
    cwd = toplevel,
    on_stdout = function(_, line: string)
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
    end,
    on_exit = function()
      callback(relpath, object_name, mode_bits, has_conflict)
    end
  }
end, 3)

M.get_staged = a.wrap(function(
  toplevel: string,
  relpath: string,
  stage: number,
  output: string,
  callback: function()
)
  -- On windows 'w' mode use \r\n instead of \n, see:
  -- https://stackoverflow.com/a/43967013
  local outf = io.open(output , 'wb')
  util.run_job {
    command = 'git',
    args = {
      '--no-pager',
      'show',
      ':'..tostring(stage)..':'..relpath,
    },
    cwd = toplevel,
    on_stdout = function(_, line: string)
      outf:write(line)
      outf:write('\n')
    end,
    on_exit = function()
      outf:close()
      callback()
    end
  }
end, 5)

M.get_staged_text = a.wrap(function(
  toplevel: string,
  relpath: string,
  stage: number,
  callback: function({string})
)
  local result = {}
  util.run_job {
    command = 'git',
    args = {
      '--no-pager',
      'show',
      ':'..tostring(stage)..':'..relpath,
    },
    cwd = toplevel,
    on_stdout = function(_, line: string)
      table.insert(result, line)
    end,
    on_exit = function()
      callback(result)
    end
  }
end, 4)

M.run_blame = a.wrap(function(
  file: string,
  toplevel: string,
  lines: {string},
  lnum: number,
  extra_args: {string},
  callback: function(M.BlameInfo)
)
  local results: {string} = {}
  util.run_job {
    command = 'git',
    args = {
      '--no-pager',
      'blame',
      '--contents', '-',
      '-L', lnum..',+1',
      '--line-porcelain',
      file,
      unpack(extra_args or {})
    },
    writer = lines,
    cwd = toplevel,
    on_stdout = function(_, line: string)
      table.insert(results, line)
    end,
    on_exit = function()
      local ret: {string:any} = {}
      if #results == 0 then
        callback({})
        return
      end
      local header = vim.split(table.remove(results, 1), ' ')
      ret.sha = header[1]
      ret.abbrev_sha = string.sub(ret.sha as string, 1, 8)
      ret.orig_lnum = tonumber(header[2]) as integer
      ret.final_lnum = tonumber(header[3]) as integer
      for _, l in ipairs(results) do
        if not startswith(l, '\t') then
          local cols = vim.split(l, ' ')
          local key = table.remove(cols, 1):gsub('-', '_')
          ret[key] = table.concat(cols, ' ')
        end
      end
      callback(ret as M.BlameInfo)
    end
  }
end, 6)

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

M.get_repo_info = a.wrap(function(
  path: string, callback: function(string,string,string))
  local out = {}

  -- Does git rev-parse have --absolute-git-dir, added in 2.13:
  --   https://public-inbox.org/git/20170203024829.8071-16-szeder.dev@gmail.com/
  local has_abs_gd = check_version{2,13}
  local git_dir_opt = has_abs_gd and '--absolute-git-dir' or '--git-dir'

  util.run_job {
    command = 'git',
    args = {'rev-parse',
      '--show-toplevel',
      git_dir_opt,
      '--abbrev-ref', 'HEAD',
    },
    cwd = path,
    on_stdout = function(_, line: string)
      if not has_abs_gd and #out == 1 then
        line = uv.fs_realpath(line)
      end
      table.insert(out, line)
    end,
    on_exit = vim.schedule_wrap(function()
      local toplevel = out[1]
      local gitdir = out[2]
      local abbrev_head = process_abbrev_head(gitdir, out[3])
      callback(toplevel, gitdir, abbrev_head)
    end)
  }
end, 2)

M.stage_lines = a.wrap(function(
  toplevel: string, lines: {string}, callback: function())
  local status = true
  local err = {}
  util.run_job {
    command = 'git',
    args = {'apply', '--cached', '--unidiff-zero', '-'},
    cwd = toplevel,
    writer = lines,
    on_stderr = function(_, line: string)
      status = false
      table.insert(err, line)
    end,
    on_exit = function()
      if not status then
        local s = table.concat(err, '\n')
        error('Cannot stage lines. Command stderr:\n\n'..s)
      end
      callback()
    end
  }
end, 3)

M.add_file = a.wrap(function(
  toplevel: string, file: string, callback: function())
  local status = true
  local err = {}
  util.run_job {
    command = 'git',
    args = {'add', '--intent-to-add', file},
    cwd = toplevel,
    on_stderr = function(_, line: string)
      status = false
      table.insert(err, line)
    end,
    on_exit = function()
      if not status then
        local s = table.concat(err, '\n')
        error('Cannot add file. Command stderr:\n\n'..s)
      end
      callback()
    end
  }
end, 3)

M.unstage_file = a.wrap(function(
  toplevel: string, file: string, callback: function())
  local status = true
  local err = {}
  util.run_job {
    command = 'git',
    args = {'reset', file},
    cwd = toplevel,
    on_stderr = function(_, line: string)
      status = false
      table.insert(err, line)
    end,
    on_exit = function()
      if not status then
        local s = table.concat(err, '\n')
        error('Cannot unstage file. Command stderr:\n\n'..s)
      end
      callback()
    end
  }
end, 3)

M.update_index = a.wrap(function(
  toplevel: string,
  mode_bits: string,
  object_name: string,
  file: string,
  callback: function()
)
  local status = true
  local err = {}
  local cacheinfo = table.concat({mode_bits, object_name, file}, ',')
  util.run_job {
    command = 'git',
    args = {'update-index', '--add', '--cacheinfo', cacheinfo},
    cwd = toplevel,
    on_stderr = function(_, line: string)
      status = false
      table.insert(err, line)
    end,
    on_exit = function()
      if not status then
        local s = table.concat(err, '\n')
        error('Cannot update index. Command stderr:\n\n'..s)
      end
      callback()
    end
  }
end, 5)

local function write_to_file(path: string, text: {string})
  local f = io.open(path, 'wb')
  for _, l in ipairs(text) do
    f:write(l)
    f:write('\n')
  end
  f:close()
end

M.run_diff = a.wrap(function(
  staged: string,
  text: {string},
  diff_algo: string,
  callback: function({Hunk})
)
  local results: {Hunk} = {}

  local buffile = staged..'_buf'
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

  util.run_job {
    command = 'git',
    args = {
      '--no-pager',
      '-c', 'core.safecrlf=false',
      'diff',
      '--color=never',
      '--diff-algorithm='..diff_algo,
      '--patch-with-raw',
      '--unified=0',
      staged,
      buffile,
    },
    on_stdout = function(_, line: string)
      if startswith(line, '@@') then
        table.insert(results, hunks.parse_diff_line(line))
      else
        if #results > 0 then
          table.insert(results[#results].lines, line)
        end
      end
    end,
    on_stderr = function(err: string, line: string)
      if err then
        gsd.eprint(err)
      end
      if line then
        gsd.eprint(line)
      end
    end,
    on_exit = function()
      os.remove(buffile)
      callback(results)
    end
  }
end, 4)

M.set_version = a.wrap(function(version: string, callback: function())
  if version ~= 'auto' then
    M.version = parse_version(version)
    callback()
    return
  end
  util.run_job {
    command = 'git', args = {'--version'},
    on_stdout = function(_, line: string)
      assert(startswith(line, 'git version'), 'Unexpected output: '..line)
      local parts = vim.split(line, '%s+')
      M.version = parse_version(parts[3])
    end,
    on_stderr = function(err: string, line: string)
      if err then
        gsd.eprint(err)
      end
      if line then
        gsd.eprint(line)
      end
    end,
    on_exit = function()
      callback()
    end
  }
end, 2)

M.command = a.wrap(function(args: {string}, callback: function({string}))
  local result: {string} = {}
  util.run_job {
    command = 'git', args = args,
    on_stdout = function(_, line: string)
      table.insert(result, line)
    end,
    on_stderr = function(err: string, line: string)
      if err then
        gsd.eprint(err)
      end
      if line then
        gsd.eprint(line)
      end
    end,
    on_exit = function()
      callback(result)
    end
  }
end, 2)

return M
