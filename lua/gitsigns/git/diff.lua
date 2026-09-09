local util = require('gitsigns.util')
local uv = vim.uv or vim.loop ---@diagnostic disable-line: deprecated

--- @class (exact) Gitsigns.DiffEntry
--- @field path string
--- @field oldpath? string
--- @field status string
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
--- @param revision string
--- @return string
local function resolve(repo, revision)
  revision = util.norm_base(revision == '' and 'HEAD' or revision) or 'HEAD'
  -- Avoid brace expansion by MSYS2 when Neovim launches Git.
  return assert(command(repo, { 'rev-parse', '--verify', revision .. '^0' })[1])
end

--- @async
--- @param repo Gitsigns.Repo
--- @param revision? string
--- @param paths? string[] Git pathspecs.
--- @param cwd? string Directory from which paths were supplied.
--- @return string? left
--- @return string? right Nil for the working tree.
--- @return Gitsigns.DiffEntry[] entries
--- @return string[]? commit Summary, author, date, and message for a single commit.
return function(repo, revision, paths, cwd)
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
  local from, dots, to
  if revision then
    from, dots, to = revision:match('^(.-)(%.%.%.?)(.-)$')
  end
  local left, right --- @type string?, string?
  local commit --- @type string[]?
  if not revision then
    local head, _, code = repo:command({ 'rev-parse', '--verify', 'HEAD' }, { ignore_error = true })
    -- Hash the empty tree without writing an object, for repositories without commits.
    left = code == 0 and head[1]
      or repo:command({ 'hash-object', '-t', 'tree', '--stdin' }, { stdin = '' })[1]
  elseif from then
    left, right = resolve(repo, from), resolve(repo, assert(to))
    if dots == '...' then
      left = assert(command(repo, { 'merge-base', left, right })[1])
    end
  else
    right = resolve(repo, revision)
    -- A merge is reviewed against its first parent. A root commit has no left side.
    commit, left = require('gitsigns.git.commit')(repo, right, 'message')
  end

  local out = command(
    repo,
    util.flatten({
      git_opts,
      revision and { 'diff-tree', '--root', '--no-commit-id', '-r' } or 'diff',
      '--raw',
      '--numstat',
      '-z',
      '--no-abbrev',
      '--find-renames',
      '--no-relative',
      left,
      right,
      '--',
      paths,
    }),
    { text = false }
  )
  -- The command helper splits on newlines; restore them before parsing NUL records.
  local fields = vim.split(table.concat(out, '\n'), '\0', { plain = true, trimempty = true })
  local entries = {} --- @type Gitsigns.DiffEntry[]
  local by_path = {} --- @type table<string, Gitsigns.DiffEntry>
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

  if not revision then
    local untracked = command(
      repo,
      util.flatten({
        git_opts,
        'ls-files',
        '--full-name',
        '--others',
        '--exclude-standard',
        '-z',
        '--',
        paths,
      }),
      { text = false }
    )
    for _, name in
      ipairs(vim.split(table.concat(untracked, '\n'), '\0', { plain = true, trimempty = true }))
    do
      local path = name:gsub('/$', '') -- Git lists nested repositories with a trailing slash.
      local stat = uv.fs_lstat(repo.toplevel .. '/' .. path)
      if stat then
        local mode = stat.type == 'link' and '120000'
          or stat.type == 'directory' and '160000'
          or '100644'
        local entry = by_path[path]
        if entry then
          -- A staged deletion can have an untracked replacement at the same path.
          entry.mode = mode
          entry.status = 'M'
        else
          entry = {
            path = path,
            status = '?',
            old_mode = '000000',
            mode = mode,
            old_oid = '',
            oid = '',
          }
          entries[#entries + 1] = entry
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
    end
  end
  return left, right, entries, commit
end
