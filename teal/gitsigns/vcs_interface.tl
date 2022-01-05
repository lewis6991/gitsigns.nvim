local gs_hunks = require("gitsigns.hunks")
local Hunk = gs_hunks.Hunk

local record GJobSpec
  command: string
  args: {string}
  cwd: string
  writer: {string}

  -- local extensions
  supress_stderr: boolean
end

local record Vcs
  in_vcs_dir: function(string): boolean
  is_inside_worktree: function(string, string): boolean

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
    previous_filename: string
    previous_sha: string
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
  get_repo_info: function(path: string, cmd: string): string,string,string
  command    : function(args: {string}, spec: GJobSpec): {string}, string

  record Repo
    toplevel   : string
    gitdir     : string
    abbrev_head: string
    username   : string

    command            : function(Repo, {string}, GJobSpec): {string}, string
    files_changed      : function(Repo): {string}
    get_show_text      : function(Repo, string): {string}, string
    update_abbrev_head : function(Repo)
    new                : function(string): Repo
  end

  record FileProps
    relpath       : string
    orig_relpath  : string -- Use for tracking moved files
    object_name   : string
    mode_bits     : string
    has_conflicts : boolean
    i_crlf        : boolean  -- Object has crlf
    w_crlf        : boolean  -- Working copy has crlf
  end

  record Obj
    repo          : Repo
    file          : string
    relpath       : string
    orig_relpath  : string -- Use for tracking moved files
    object_name   : string
    mode_bits     : string
    has_conflicts : boolean
    i_crlf        : boolean  -- Object has crlf
    w_crlf        : boolean  -- Working copy has crlf

    command              : function(Obj, {string}, GJobSpec): {string}, string
    update_file_info     : function(Obj, boolean): boolean
    unstage_file         : function(Obj, string, string)
    run_blame            : function(Obj, {string}, number, boolean): BlameInfo
    file_info            : function(Obj, string): FileProps
    get_show_text        : function(Obj, string): {string}, string
    ensure_file_in_index : function(Obj)
    stage_hunks          : function(Obj, {Hunk}, boolean)
    has_moved            : function(Obj): string
    new                  : function(string): Obj
  end

end

local record M
    new_vcs    : function(): Vcs
    g_job_spec : GJobSpec
end

M.new_vcs = function(): Vcs
  local self = setmetatable({} as Vcs, {__index = Vcs})
  return self
end

return M
