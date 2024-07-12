local uv = vim.uv or vim.loop

local error_once = require('gitsigns.message').error_once
local log = require('gitsigns.debug.log')

--- @class Gitsigns.CommitInfo
--- @field author string
--- @field author_mail string
--- @field author_time integer
--- @field author_tz string
--- @field committer string
--- @field committer_mail string
--- @field committer_time integer
--- @field committer_tz string
--- @field summary string
--- @field sha string
--- @field abbrev_sha string
--- @field boundary? true

--- @class Gitsigns.BlameInfoPublic: Gitsigns.BlameInfo, Gitsigns.CommitInfo
--- @field body? string[]
--- @field hunk_no? integer
--- @field num_hunks? integer
--- @field hunk? string[]
--- @field hunk_head? string

--- @class Gitsigns.BlameInfo
--- @field orig_lnum integer
--- @field final_lnum integer
--- @field commit Gitsigns.CommitInfo
--- @field filename string
--- @field previous_filename? string
--- @field previous_sha? string

local NOT_COMMITTED = {
  author = 'Not Committed Yet',
  author_mail = '<not.committed.yet>',
  committer = 'Not Committed Yet',
  committer_mail = '<not.committed.yet>',
}

local M = {}

--- @param file string
--- @return Gitsigns.CommitInfo
local function not_committed(file)
  local time = os.time()
  return {
    sha = string.rep('0', 40),
    abbrev_sha = string.rep('0', 8),
    author = 'Not Committed Yet',
    author_mail = '<not.committed.yet>',
    author_tz = '+0000',
    author_time = time,
    committer = 'Not Committed Yet',
    committer_time = time,
    committer_mail = '<not.committed.yet>',
    committer_tz = '+0000',
    summary = 'Version of ' .. file,
  }
end

--- @param file string
--- @param lnum integer
--- @return Gitsigns.BlameInfo
function M.get_blame_nc(file, lnum)
  return {
    orig_lnum = 0,
    final_lnum = lnum,
    commit = not_committed(file),
    filename = file,
  }
end

---@param x any
---@return integer
local function asinteger(x)
  return assert(tonumber(x))
end

--- @param readline fun(): string?
--- @param commits table<string,Gitsigns.CommitInfo>
--- @param result table<integer,Gitsigns.BlameInfo>
local function incremental_iter(readline, commits, result)
  local line = assert(readline())

  --- @type string, string, string, string
  local sha, orig_lnum_str, final_lnum_str, size_str = line:match('(%x+) (%d+) (%d+) (%d+)')
  assert(sha)

  local orig_lnum = asinteger(orig_lnum_str)
  local final_lnum = asinteger(final_lnum_str)
  local size = asinteger(size_str)

  --- @type table<string,string|true>
  local commit = commits[sha] or {
    sha = sha,
    abbrev_sha = sha:sub(1, 8),
  }

  --- @type string, string
  local previous_sha, previous_filename

  line = assert(readline())

  -- filename terminates the entry
  while not line:match('^filename ') do
    local key, value = line:match('^([^%s]+) (.*)')
    if key == 'previous' then
      previous_sha, previous_filename = line:match('^previous (%x+) (.*)')
    elseif key then
      key = key:gsub('%-', '_') --- @type string
      if vim.endswith(key, '_time') then
        value = tonumber(value)
      end
      commit[key] = value
    else
      commit[line] = true
      if line ~= 'boundary' then
        log.dprintf("Unknown tag: '%s'", line)
      end
    end
    line = assert(readline())
  end

  local filename = assert(line:match('^filename (.*)'))

  -- New in git 2.41:
  -- The output given by "git blame" that attributes a line to contents
  -- taken from the file specified by the "--contents" option shows it
  -- differently from a line attributed to the working tree file.
  if
    commit.author_mail == '<external.file>'
    or commit.author_mail == 'External file (--contents)'
  then
    commit = vim.tbl_extend('force', commit, NOT_COMMITTED)
  end
  commits[sha] = commit

  for j = 0, size - 1 do
    result[final_lnum + j] = {
      final_lnum = final_lnum + j,
      orig_lnum = orig_lnum + j,
      commit = commits[sha],
      filename = filename,
      previous_filename = previous_filename,
      previous_sha = previous_sha,
    }
  end
end

--- @param data string
--- @return string[]
local function data_to_lines(data)
  local lines = vim.split(data, '\n')
  if lines[#lines] == '' then
    lines[#lines] = nil
  end
  return lines
end

--- @param f fun(readline: fun(): string?))
--- @return fun(data: string?)
local function bufferred_line_reader(f)
  --- @param data string?
  return coroutine.wrap(function(data)
    if not data then
      return
    end

    local data_lines = data_to_lines(data)
    local i = 0

    local function readline(peek)
      if not data_lines[i + 1] then
        data = coroutine.yield()
        if not data then
          return
        end
        data_lines = data_to_lines(data)
        i = 0
      end

      if peek then
        return data_lines[ i+ 1]
      end
      i = i + 1
      return data_lines[i]
    end

    while readline(true) do
      f(readline)
    end
  end)
end

--- @param obj Gitsigns.GitObj
--- @param lines string[]
--- @param lnum? integer
--- @param revision? string
--- @param opts? Gitsigns.BlameOpts
--- @return table<integer, Gitsigns.BlameInfo>
function M.run_blame(obj, lines, lnum, revision, opts)
  local ret = {} --- @type table<integer,Gitsigns.BlameInfo>

  if not obj.object_name or obj.repo.abbrev_head == '' then
    -- As we support attaching to untracked files we need to return something if
    -- the file isn't isn't tracked in git.
    -- If abbrev_head is empty, then assume the repo has no commits
    local commit = not_committed(obj.file)
    for i in ipairs(lines) do
      ret[i] = {
        orig_lnum = 0,
        final_lnum = i,
        commit = commit,
        filename = obj.file,
      }
    end
    return ret
  end

  local args = { 'blame', '--contents', '-', '--incremental' }

  opts = opts or {}

  if opts.ignore_whitespace then
    args[#args + 1] = '-w'
  end

  if lnum then
    vim.list_extend(args, { '-L', lnum .. ',+1' })
  end

  if opts.extra_opts then
    vim.list_extend(args, opts.extra_opts)
  end

  local ignore_file = obj.repo.toplevel .. '/.git-blame-ignore-revs'
  if uv.fs_stat(ignore_file) then
    vim.list_extend(args, { '--ignore-revs-file', ignore_file })
  end

  args[#args + 1] = revision
  args[#args + 1] = '--'
  args[#args + 1] = obj.file

  local commits = {} --- @type table<string,Gitsigns.CommitInfo>

  local reader = bufferred_line_reader(function(readline)
    incremental_iter(readline, commits, ret)
  end)

  --- @param data string?
  local function on_stdout(_, data)
    reader(data)
  end

  local _, stderr = obj.repo:command(args, { stdin = lines, stdout = on_stdout, ignore_error = true })

  if stderr then
    error_once('Error running git-blame: ' .. stderr)
    return {}
  end

  return ret
end

return M
