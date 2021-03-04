
global _: any

global record CacheEntry
  file          : string
  relpath       : string
  object_name   : string
  mode_bits     : string
  toplevel      : string
  gitdir        : string
  staged        : string
  abbrev_head   : string
  has_conflicts : boolean
  hunks         : {Hunk}
  staged_diffs  : {Hunk}
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
  keymaps: {string:string}
end

global record StatusObj
    added: number
    removed: number
    changed: number
    head: string
end

global record Config
    debug_mode: boolean
    diff_algorithm: string
    signs: {SignType: SignsConfig}
    count_chars: {string|number:string}
    numhl: boolean
    sign_priority: number
    keymaps: {string:any}
    record watch_index
        interval: number
    end
    max_file_length: number
    update_debounce: number
    status_formatter: function(StatusObj): string
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
  lnum: number
  count: number
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
  start: number
  dend: number

  record Node
    start: number
    count: number
  end

  added: Node
  removed: Node
end

