local util = require('gitsigns.util')
local FileMode = require('gitsigns.git').FileMode
local uv = vim.uv

--- @alias Gitsigns.DiffSectionKind 'unstaged'|'staged'

--- @class (exact) Gitsigns.DiffSection
--- @field kind? Gitsigns.DiffSectionKind Nil for an explicit revision comparison.
--- @field entries Gitsigns.DiffEntry[]

--- @class (exact) Gitsigns.DiffEntry
--- @field path string
--- @field oldpath? string
--- @field status string One column per comparison, or two columns for an explicit base vs worktree.
--- @field index_paths? string[]
--- @field worktree_paths? string[]
--- @field old_mode string
--- @field mode string
--- @field worktree_mode? string Preview target for a staged row.
--- @field old_oid string
--- @field oid string
--- @field added integer? Nil for binary files.
--- @field removed integer? Nil for binary files.

--- @class (exact) Gitsigns.DiffStatus
--- @field path string
--- @field status string Index and worktree status columns.
--- @field mode? string Worktree mode.
--- @field oldpath? string Rename or copy origin.
--- @field ours_mode? string Stage 2 mode for an unmerged path.
--- @field ours_oid? string Stage 2 object ID for an unmerged path.

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
--- @return Gitsigns.DiffStatus[]
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
  local entries = {} --- @type Gitsigns.DiffStatus[]
  local i = 1

  while i <= #records do
    local record = assert(records[i])
    local kind = record:sub(1, 1)

    if kind == '?' then
      -- Nested repositories are listed with a trailing slash.
      entries[#entries + 1] = { path = record:sub(3):gsub('/$', ''), status = '??' }
    elseif kind == '1' or kind == '2' or kind == 'u' then
      local status, mode, path, ours_mode, ours_oid
      if kind == 'u' then
        -- Stage 2 is the comparison base for unmerged files.
        status, ours_mode, mode, ours_oid, path =
          record:match('^u (..) %S+ %d+ (%d+) %d+ (%d+) %x+ (%x+) %x+ (.*)$')
      else
        status, mode, path = record:match('^[12] (..) %S+ %d+ %d+ (%d+) %x+ %x+ (.*)$')
      end
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
        ours_mode = ours_mode,
        ours_oid = ours_oid,
      }
    end
    i = i + 1
  end

  return entries
end

--- @param path string
--- @param index_mode? string
--- @return Gitsigns.GitFileMode?
local function worktree_mode(path, index_mode)
  local stat = uv.fs_lstat(path)
  if not stat then
    return
  elseif stat.type == 'file' then
    return FileMode.regular
  elseif stat.type == 'link' then
    return FileMode.symlink
  elseif
    stat.type == 'directory' and (index_mode == FileMode.gitlink or uv.fs_lstat(path .. '/.git'))
  then
    -- A submodule checkout can be uninitialized.
    return FileMode.gitlink
  end
end

--- Add an untracked path, including a replacement for a staged deletion.
--- @async
--- @param repo Gitsigns.Repo
--- @param path string
--- @param entries Gitsigns.DiffEntry[]
--- @param by_path table<string, Gitsigns.DiffEntry>
--- @return Gitsigns.DiffEntry?
local function add_untracked(repo, path, entries, by_path)
  local mode = worktree_mode(repo.toplevel .. '/' .. path)
  if not mode then
    return
  end
  local entry = by_path[path]
  if entry then
    -- A staged deletion can have an untracked replacement at the same path.
    entry.mode = mode
    entry.status = entry.status:sub(1, 1) .. '?'
  else
    entry = {
      path = path,
      status = '??',
      old_mode = FileMode.missing,
      mode = mode,
      old_oid = '',
      oid = '',
    }
    entries[#entries + 1] = entry
    by_path[path] = entry
  end

  if mode == FileMode.gitlink then
    -- Untracked repositories are displayed as one added gitlink line.
    entry.added, entry.removed = 1, entry.removed or 0
  else
    -- The index omits these paths. Compare replacements directly with
    -- their old blob, and new files with an empty file.
    local sides = entry.old_mode ~= FileMode.missing and { entry.old_oid, '--', './' .. path }
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
  return entry
end

--- Read each side of the index independently for the default diff panel.
--- @async
--- @param repo Gitsigns.Repo
--- @param base string
--- @param git_opts string[]
--- @param paths string[]
--- @return Gitsigns.DiffSection[]
local function read_worktree_diff(repo, base, git_opts, paths)
  -- Exclude raw U records. For conflicts Git can emit a second record with
  -- the actual diff against our side, which supplies the modes and diffstat.
  local args = { git_opts, 'diff', '--diff-filter=u', '--ita-invisible-in-index' }
  local unstaged, unstaged_by_path = read_diff(repo, util.flatten({ args, '--ours' }), paths)
  local staged = read_diff(repo, util.flatten({ args, '--cached', base }), paths)

  for _, change in ipairs(read_status(repo, git_opts, paths)) do
    if change.status == '??' then
      local entry = add_untracked(repo, change.path, unstaged, unstaged_by_path)
      if entry then
        entry.status = '?'
      end
    elseif change.ours_mode then
      local entry = unstaged_by_path[change.path]
      if entry then
        entry.status = 'U'
      else
        -- Keep unresolved paths visible even when they match our side exactly.
        unstaged[#unstaged + 1] = {
          path = change.path,
          status = 'U',
          old_mode = change.ours_mode,
          old_oid = assert(change.ours_oid),
          mode = assert(change.mode),
          oid = '',
          added = 0,
          removed = 0,
        }
      end
    end
  end

  -- Staged rows describe the index and display the working file.
  for _, entry in ipairs(staged) do
    entry.worktree_mode = worktree_mode(repo.toplevel .. '/' .. entry.path, entry.mode)
      or FileMode.missing
  end

  return {
    { kind = 'unstaged', entries = unstaged },
    { kind = 'staged', entries = staged },
  }
end

--- @async
--- @param repo Gitsigns.Repo
--- @param revision? string
--- @param paths? string[] Git pathspecs.
--- @param cwd? string Directory from which paths were supplied.
--- @param show_commit? boolean Compare a commit with its first parent.
--- @return string? base Base revision; nil when showing a root commit.
--- @return string? target Target revision; nil for the working tree.
--- @return Gitsigns.DiffSection[] sections
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
    return base, nil, read_worktree_diff(repo, assert(base), git_opts, paths)
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
            old_mode = mode or FileMode.missing,
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

  return base, target, { { entries = entries } }, commit
end
