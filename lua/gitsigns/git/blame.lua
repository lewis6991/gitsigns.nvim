local uv = vim.uv or vim.loop

local error_once = require('gitsigns.message').error_once
local dprintf = require('gitsigns.debug.log').dprintf

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

--- @param data_lines string[]
--- @param i integer
--- @param commits table<string,Gitsigns.CommitInfo>
--- @param result table<integer,Gitsigns.BlameInfo>
--- @return integer i
--- @return integer? size
local function incremental_iter(data_lines, i, commits, result)
  local line = assert(data_lines[i])
  i = i + 1

  --- @type string, string, string, string
  local sha, orig_lnum_str, final_lnum_str, size_str = line:match('(%x+) (%d+) (%d+) (%d+)')
  if not sha then
    return i
  end

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

  -- filename terminates the entry
  while data_lines[i] and not data_lines[i]:match('^filename ') do
    local l = assert(data_lines[i])
    i = i + 1
    local key, value = l:match('^([^%s]+) (.*)')
    if key == 'previous' then
      previous_sha, previous_filename = data_lines[i]:match('^previous (%x+) (.*)')
    elseif key then
      key = key:gsub('%-', '_') --- @type string
      if vim.endswith(key, '_time') then
        value = tonumber(value)
      end
      commit[key] = value
    else
      commit[l] = true
      if l ~= 'boundary' then
        dprintf("Unknown tag: '%s'", l)
      end
    end
  end

  local filename = assert(data_lines[i]:match('^filename (.*)'))

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

  return i, size
end

--- @param data? string
--- @param commits table<string,Gitsigns.CommitInfo>
--- @param result table<integer,Gitsigns.BlameInfo>
--- @param progress_cb? fun(size: number)
local function process_incremental(data, commits, result, progress_cb)
  if not data then
    return
  end

  local data_lines = vim.split(data, '\n')
  local i = 1

  while i <= #data_lines do
    local size
    i, size = incremental_iter(data_lines, i, commits, result)
    if size and progress_cb then
      progress_cb(size)
    end
  end
end

--- @param lines string[]
--- @param progress_cb? fun(pct: integer)
--- @return fun(size: integer)?
local function build_progress_cb(lines, progress_cb)
  if not progress_cb then
    return
  end

  local total = #lines

  local processed = 0
  local last_r --- @type integer?

  return function(size)
    --- @type integer
    processed = processed + size
    local r = math.floor(processed * 100 / total)
    if r ~= last_r then
      progress_cb(r)
    end
    last_r = r
  end
end

--- @param obj Gitsigns.GitObj
--- @param lines string[]
--- @param lnum? integer
--- @param revision? string
--- @param opts? Gitsigns.BlameOpts
--- @param progress_cb? fun(pct: integer)
--- @return table<integer, Gitsigns.BlameInfo>
function M.run_blame(obj, lines, lnum, revision, opts, progress_cb)
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

  local progress_cb1 = build_progress_cb(lines, progress_cb)

  --- @param data string?
  local function on_stdout(_, data)
    process_incremental(data, commits, ret, progress_cb1)
  end

  local _, stderr = obj:command(args, { stdin = lines, stdout = on_stdout, ignore_error = true })

  if stderr then
    error_once('Error running git-blame: ' .. stderr)
    return {}
  end

  return ret
end

return M
