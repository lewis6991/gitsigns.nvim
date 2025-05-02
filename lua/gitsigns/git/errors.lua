return {
  e = {
    worktree = vim.pesc('fatal: this operation must be run in a work tree'),
    -- Match both:
    --   'fatal: not a git repository (or any of the parent directories)'
    --   'fatal: not a git repository (or any parent up to mount point /)'
    not_in_git = 'fatal: not a git repository',
    path_does_not_exist = "fatal: path .* does not exist in '.*'",
    path_exist_on_disk_but_not_in = "fatal: path .* exists on disk, but not in '.*'",
    path_is_outside_worktree = "fatal: .*: '.*' is outside repository at '.*'",
    ambiguous_head = "fatal: ambiguous argument 'HEAD'",
  },
  w = {
    could_not_open_directory = '^warning: could not open directory .*: No such file or directory',
  },
}
