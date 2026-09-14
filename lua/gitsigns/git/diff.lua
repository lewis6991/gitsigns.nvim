local util = require('gitsigns.util')
local uv = vim.uv or vim.loop ---@diagnostic disable-line: deprecated

--- @class (exact) Gitsigns.DiffEntry
--- @field path string
--- @field oldpath? string
--- @field status string One column for revisions; index and worktree columns otherwise.
--- @field index_paths? string[]
--- @field worktree_paths? string[]
--- @field old_mode string
--- @field mode string
--- @field old_oid string
--- @field oid string
--- @field added integer? Nil for binary files.
--- @field removed integer? Nil for binary files.

--- @async
--- @param repo Gitsigns.Repo
--- @param args string[]
--- @param opts? Gitsigns.Git.JobSpec
--- @return string[]
local function command(repo, args, opts)
  opts = opts or {}
  opts.ignore_error = true

  -- Normalize line endings in metadata; raw filename records opt out.
  local out, err, code = repo:command(args, opts)
  if code ~= 0 then
    error(err or 'Unable to read revision', 0)
  end

  return out
end

--- @async
--- @param repo Gitsigns.Repo
--- @param revision? string Defaults to HEAD.
--- @return string
local function resolve(repo, revision)
  revision = util.norm_base(revision == '' and 'HEAD' or revision) or 'HEAD'

  -- Avoid brace expansion by MSYS2 when Neovim launches Git.
  return assert(command(repo, { 'rev-parse', '--verify', revision .. '^0' })[1])
end

--- Read raw changes and their diffstats from the same Git invocation.
--- @async
--- @param repo Gitsigns.Repo
--- @param args string[]
--- @param paths string[]
--- @return Gitsigns.DiffEntry[]
--- @return table<string, Gitsigns.DiffEntry>
local function read_diff(repo, args, paths)
  local out = command(
    repo,
    util.flatten({
      args,
      '--raw',
      '--numstat',
      '-z',
      '--no-abbrev',
      '--find-renames',
      '--no-relative',
      '--',
      paths,
    }),
    { text = false }
  )

  -- The command helper splits on newlines; restore them before parsing NUL records.
  local fields = vim.split(table.concat(out, '\n'), '\0', { plain = true, trimempty = true })
  local entries = {} --- @type Gitsigns.DiffEntry[]
  local by_path = {} --- @type table<string, Gitsigns.DiffEntry>

  -- First build entries from raw records, including both paths for renames.
  local i = 1
  while i <= #fields and assert(fields[i]):sub(1, 1) == ':' do
    local old_mode, mode, old_oid, oid, status =
      assert(fields[i]):match('^:(%d+) (%d+) (%x+) (%x+) (%w+)$')
    assert(status, 'Invalid diff record')

    local path, oldpath = assert(fields[i + 1]), nil
    i = i + 2
    if status:sub(1, 1) == 'R' or status:sub(1, 1) == 'C' then
      oldpath, path = path, assert(fields[i])
      i = i + 1
    end

    local entry = {
      path = path,
      oldpath = oldpath,
      status = status:sub(1, 1),
      old_mode = assert(old_mode),
      mode = assert(mode),
      old_oid = assert(old_oid),
      oid = assert(oid),
    }
    entries[#entries + 1] = entry
    by_path[path] = entry
  end

  -- Git emits raw records first, followed by numstat records. Renames have
  -- an empty path in the stat record, then separate old and new path fields.
  while i <= #fields do
    local added, removed, path = assert(fields[i]):match('^([%d-]+)\t([%d-]+)\t(.*)$')
    assert(path, 'Invalid numstat record')
    if path == '' then
      path = assert(fields[i + 2])
      i = i + 2
    end

    local entry = by_path[path]
    entry.added, entry.removed = tonumber(added), tonumber(removed)
    i = i + 1
  end

  return entries, by_path
end

--- Read staging status independently of the revision being compared.
--- @async
--- @param repo Gitsigns.Repo
--- @param git_opts string[]
--- @param paths string[]
--- @return {path:string, status:string, mode?:string, oldpath?:string}[]
local function read_status(repo, git_opts, paths)
  local out = command(
    repo,
    util.flatten({
      git_opts,
      'status',
      '--porcelain=v2',
      '-z',
      '--untracked-files=all',
      '--renames',
      '--',
      paths,
    }),
    { text = false }
  )

  -- NUL delimiters preserve whitespace and newlines within filenames.
  local records = vim.split(table.concat(out, '\n'), '\0', { plain = true, trimempty = true })
  local entries = {}
  local i = 1

  while i <= #records do
    local record = assert(records[i])
    local kind = record:sub(1, 1)

    if kind == '?' then
      -- Nested repositories are listed with a trailing slash.
      entries[#entries + 1] = { path = record:sub(3):gsub('/$', ''), status = '??' }
    elseif kind == '1' or kind == '2' or kind == 'u' then
      -- Ordinary/renamed records contain HEAD/index modes and hashes; unmerged
      -- records contain three stages. Retain the worktree mode and status.
      local pattern = kind == 'u' and '^u (..) %S+ %d+ %d+ %d+ (%d+) %x+ %x+ %x+ (.*)$'
        or '^[12] (..) %S+ %d+ %d+ (%d+) %x+ %x+ (.*)$'
      local status, mode, path = record:match(pattern)
      assert(status and mode and path, 'Invalid status record')

      -- Renames have a score before the path and the origin in the next NUL record.
      local oldpath
      if kind == '2' then
        path = assert(path:match('^%S+ (.*)$')) -- Skip the rename/copy score.
        i = i + 1
        oldpath = assert(records[i])
      end

      -- Use the panel's blank status columns instead of porcelain's dots.
      entries[#entries + 1] = {
        path = path,
        status = status:gsub('%.', ' '),
        mode = mode,
        oldpath = oldpath,
      }
    end
    i = i + 1
  end

  return entries
end

--- Add an untracked path, including a replacement for a staged deletion.
--- @async
--- @param repo Gitsigns.Repo
--- @param path string
--- @param entries Gitsigns.DiffEntry[]
--- @param by_path table<string, Gitsigns.DiffEntry>
local function add_untracked(repo, path, entries, by_path)
  local stat = uv.fs_lstat(repo.toplevel .. '/' .. path)
  if not stat then
    return
  end

  local mode = stat.type == 'link' and '120000' or stat.type == 'directory' and '160000' or '100644'
  local entry = by_path[path]
  if entry then
    -- A staged deletion can have an untracked replacement at the same path.
    entry.mode = mode
    entry.status = entry.status:sub(1, 1) .. '?'
  else
    entry = {
      path = path,
      status = '??',
      old_mode = '000000',
      mode = mode,
      old_oid = '',
      oid = '',
    }
    entries[#entries + 1] = entry
    by_path[path] = entry
  end

  if stat.type == 'directory' then
    -- Untracked repositories are displayed as one added gitlink line.
    entry.added, entry.removed = 1, entry.removed or 0
  else
    -- The index omits these paths. Compare replacements directly with
    -- their old blob, and new files with an empty file.
    local sides = entry.old_mode ~= '000000' and { entry.old_oid, '--', './' .. path }
      or { '--no-index', '--', '/dev/null', './' .. path }
    local stats, stats_err, code = repo:command(
      util.flatten({ 'diff', '--numstat', '-z', sides }),
      { text = false, ignore_error = true }
    )
    if code > 1 then -- --no-index returns 1 when files differ.
      error(stats_err or 'Unable to read diffstat', 0)
    end

    local record = stats[1] ~= '' and assert(stats[1]) or '0\t0\t'
    local added, removed = record:match('^([%d-]+)\t([%d-]+)\t')
    entry.added, entry.removed = tonumber(added), tonumber(removed)
  end
end

--- @async
--- @param repo Gitsigns.Repo
--- @param revision? string
--- @param paths? string[] Git pathspecs.
--- @param cwd? string Directory from which paths were supplied.
--- @param show_commit? boolean Compare a commit with its first parent.
--- @return string? base Base revision; nil when showing a root commit.
--- @return string? target Target revision; nil for the working tree.
--- @return Gitsigns.DiffEntry[] entries
--- @return string[]? commit Summary, author, date, and message for a single commit.
return function(repo, revision, paths, cwd, show_commit)
  paths = paths or {}

  -- Use Git's path format (POSIX for MSYS2) so it can find cwd within the
  -- worktree and apply pathspec prefixes when running from a subdirectory.
  local git_opts = #paths > 0
      and {
        '--no-literal-pathspecs',
        '--work-tree',
        assert(command(repo, { '--work-tree', '.', 'rev-parse', '--show-toplevel' })[1]),
        '-C',
        cwd or vim.fn.getcwd(),
      }
    or {}

  -- Resolve revision arguments before reading the compared paths.
  local from, dots, to
  if revision then
    from, dots, to = revision:match('^(.-)(%.%.%.?)(.-)$')
  end

  local base, target --- @type string?, string?
  local commit --- @type string[]?
  if show_commit then
    target = resolve(repo, revision)

    -- A merge is reviewed against its first parent. A root commit has no parent.
    commit, base = require('gitsigns.git.commit')(repo, target, 'message')
  elseif not revision then
    local head, _, code = repo:command({ 'rev-parse', '--verify', 'HEAD' }, { ignore_error = true })

    -- Hash the empty tree without writing an object, for repositories without commits.
    base = code == 0 and head[1]
      or repo:command({ 'hash-object', '-t', 'tree', '--stdin' }, { stdin = '' })[1]
  elseif from then
    base, target = resolve(repo, from), resolve(repo, assert(to))
    if dots == '...' then
      base = assert(command(repo, { 'merge-base', base, target })[1])
    end
  else
    base = resolve(repo, revision)
  end

  -- This diff supplies the file list and stats for the selected comparison.
  local entries, by_path = read_diff(
    repo,
    util.flatten({
      git_opts,
      target and { 'diff-tree', '--root', '--no-commit-id', '-r', base, target }
        or { 'diff', base },
    }),
    paths
  )

  -- Staging status is always relative to HEAD/index, even for an older display base.
  if not target then
    for _, entry in ipairs(entries) do
      entry.status = '  '
    end

    for _, change in ipairs(read_status(repo, git_opts, paths)) do
      local path = change.path
      if change.status == '??' then
        add_untracked(repo, path, entries, by_path)
      else
        local entry = by_path[path]
        if not entry then
          -- Changes can cancel out in the displayed diff. Keep these files
          -- available for staging, using the selected base rather than HEAD.
          local tree = command(repo, {
            '--literal-pathspecs',
            'ls-tree',
            '-z',
            assert(base),
            '--',
            path,
          }, { text = false })
          local mode, oid = table.concat(tree, '\n'):match('^(%d+) %w+ (%x+)\t')

          entry = {
            path = path,
            status = change.status,
            old_mode = mode or '000000',
            old_oid = oid or '',
            mode = assert(change.mode),
            oid = '',
            added = 0,
            removed = 0,
          }
          entries[#entries + 1] = entry
          by_path[path] = entry
        end

        entry.status = change.status

        -- A staging action must include the origin on the side that contains the rename.
        if change.oldpath then
          if change.status:sub(1, 1):match('[RC]') then
            entry.index_paths = { path, change.oldpath }
          end
          if change.status:sub(2, 2):match('[RC]') then
            entry.worktree_paths = { path, change.oldpath }
          end
        end
      end
    end
  end

  return base, target, entries, commit
end
