
global _: any

global record CacheEntry
  file          : string
  relpath       : string
  object_name   : string
  mode_bits     : string
  toplevel      : string
  gitdir        : string
  staged        : string
  staged_text   : {string}
  abbrev_head   : string
  has_conflicts : boolean
  hunks         : {Hunk}
  staged_diffs  : {Hunk}
  pending_signs : {integer:Sign}
  index_watcher : vim.loop.FSPollObj          -- Timer object watching the files index
end

global enum SignName
  "GitSignsAdd"
  "GitSignsDelete"
  "GitSignsChange"
  "GitSignsTopDelete"
  "GitSignsChangeDelete"
end

global record SignsConfig
  show_count: boolean
  hl: string
  text: string
  numhl: string
  linehl: string
  keymaps: {string:string}
end

global record StatusObj
    added   : integer
    removed : integer
    changed : integer
    head    : string
end

global record Config
    debug_mode: boolean
    diff_algorithm: string
    signs: {SignType: SignsConfig}
    count_chars: {string|integer:string}
    signcolumn: boolean
    numhl: boolean
    linehl: boolean
    sign_priority: integer
    keymaps: {string:any}
    record watch_index
        interval: integer
    end
    max_file_length: integer
    update_debounce: integer
    status_formatter: function(StatusObj): string
    use_internal_diff: boolean
    use_decoration_api: boolean

    -- Undocumented
    _refresh_staged_on_update: boolean
end

global enum SignType
  "add"
  "delete"
  "change"
  "topdelete"
  "changedelete"
end

global record Sign
  type: SignType
  count: integer
end

global record Hunk
  enum Type
    "add"
    "change"
    "delete"
  end

  type: Type
  head: string
  lines: {string}
  start: integer
  dend: integer

  record Node
    start: integer
    count: integer
  end

  added: Node
  removed: Node
end

