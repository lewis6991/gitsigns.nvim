-- Jujutsu (vcs) detection utilities

local Path = require('gitsigns.util').Path
local uv = vim.uv or vim.loop

local M = {}

-- Walk up from `dir` looking for a `.jj` directory.
-- This should only be called after the git discovery.
-- The walk stops when a `.jj` directory is found or when a `.git` dir is found.
-- When a `.git` dir is found then there will not be a `.jj` dir in the repo
-- (the git discovery should have already run).
--
-- Returns the path to the jj_dir (nil if none was found)
--
--- @param dir string
--- @return string? jj_dir
local function find_jj_dir(dir)
  local cur = dir
  while cur do
    if uv.fs_stat(Path.join(cur, '.jj')) then
      return Path.join(cur, '.jj')
    end
    if uv.fs_stat(Path.join(cur, '.git')) then
      return nil
    end
    local parent = vim.fs.dirname(cur)
    if not parent or parent == cur then
      return nil
    end
    cur = parent
  end
end

-- Resolve the authoritative `.jj/repo` directory for a given local `.jj`
-- directory. A `.jj` repo can refer to three situations.
-- 1. A colocated repo.
--    There is a `.git` repo alongside it the `.jj` dir.
--    We can ignore it, because gitsigns can work off the `.git` dir.
-- 2. An uncolocated repo.
--    The `.jj` dir has an internal (bare) git repo (usually) in `.jj/repo/store/git`
-- 3. A workspace. A `jj` workspace is similar to a git worktree.
--    There, the `.jj` dir has a pointer to the authoritative checkout in `.jj/repo`
--
-- In summary. If `<jj_dir>/repo` is itself a directory, that's it.
-- If it's a file (a workspace), its contents are a path (relative to
-- `jj_dir`, or absolute) pointing at the authoritative `.jj/repo` directory
-- elsewhere.
--
--- @param jj_dir string
--- @return string? repo_dir
local function resolve_repo_dir(jj_dir)
  local repo_path = Path.join(jj_dir, 'repo')
  local stat = uv.fs_stat(repo_path)
  if not stat then
    return nil
  end
  if stat.type == 'directory' then
    return repo_path
  end
  if stat.type ~= 'file' then
    return nil
  end
  local fd = io.open(repo_path, 'r')
  if not fd then
    return nil
  end
  local raw = fd:read('*a')
  fd:close()
  local target = raw and vim.trim(raw) or ''
  if target == '' then
    return nil
  end
  if not Path.is_abs(target) then
    target = Path.join(jj_dir, target)
  end
  if uv.fs_stat(target) then
    return target
  end
  return nil
end

-- Read `store/git_target` inside a `.jj/repo` directory and resolve it into
-- an absolute path to the backing git directory. The file's content is the
-- source of truth a path relative to the `store` directory it lives in (this
-- matches jj's documented on-disk layout), or occasionally absolute;
-- handle both.
--- @param repo_dir string
--- @return string? gitdir
local function resolve_git_target(repo_dir)
  local store_dir = Path.join(repo_dir, 'store')
  local target_path = Path.join(store_dir, 'git_target')
  local fd = io.open(target_path, 'r')
  if not fd then
    return nil
  end
  local raw = fd:read('*a')
  fd:close()
  local target = raw and vim.trim(raw) or ''
  if target == '' then
    return nil
  end
  local gitdir = Path.is_abs(target) and target or Path.join(store_dir, target)
  gitdir = uv.fs_realpath(gitdir)
  if not gitdir or not uv.fs_stat(gitdir) then
    return nil
  end
  return gitdir
end

--- Resolve a jj-backed git directory and worktree for `dir`, without ever
--- invoking the `jj` binary. Returns nil (both values) if `dir` is not
--- inside a jj repo, or if any expected file is missing, unreadable, or
--- dangling (e.g. a non-git jj backend, a stale workspace pointer).
--- @param dir string
--- @return string? gitdir
--- @return string? worktree
function M.resolve(dir)
  local jj_dir = find_jj_dir(dir)
  if not jj_dir then
    return nil
  end
  local repo_dir = resolve_repo_dir(jj_dir)
  if not repo_dir then
    return nil
  end
  local gitdir = resolve_git_target(repo_dir)
  if not gitdir then
    return nil
  end
  local worktree = vim.fs.dirname(jj_dir)
  return gitdir, worktree
end

return M
