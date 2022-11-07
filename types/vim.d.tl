local api = require 'vim.api'
local fn = require 'vim.fn'
local uv = require 'vim.uv'

local record M
  api: api
  fn: fn

  call: function(string, ...:any)
  cmd: function(string): any

  deepcopy: function<T>(T): T

  defer_fn: function(function, integer): uv.Timer

  type DiffResult = {integer, integer, integer, integer}

  -- Assume result_type == 'indices'
  diff: function(string|{string}, string|{string}, table): {DiffResult}

  env: {string:string}

  iconv: function(string, string, string): string

  is_callable: function(any): boolean

  record go
    operatorfunc: string
  end

  record o
    diffopt: string
    eventignore: string
    shortmess: string
    splitright: boolean
    updatetime: number
    wrapscan: boolean
  end

  record WinOption
    {WinOption}
    diff: boolean
    signcolumn: string
    scrolloff: integer
    relativenumber: boolean
  end

  wo: WinOption

  record BufOption
    {BufOption}
    fileformat: string
    fileencoding: string
    filetype: string
    modifiable: boolean
    modified: boolean
    tabstop: integer

    enum BufHidden
      '' 'hide' 'unload' 'delete' 'wipe'
    end

    bufhidden: BufHidden

    enum BufType
      '' 'acwrite' 'help' 'nofile' 'nowrite' 'quickfix' 'terminal' 'prompt'
    end
    buftype: BufType
  end

  bo: BufOption

  record BufVar
    {BufVar}
    changedtick: integer

    gitsigns_head: string
    gitsigns_status_dict: {string:any}
    gitsigns_status: string
    gitsigns_blame_line_dict: {string:any}
    gitsigns_blame_line: string
  end

  b: BufVar

  record WinVar
    {WinVar}

    gitsigns_preview: string|boolean
  end

  w: WinVar

  record g
    gitsigns_head: string
    loaded_fugitive: integer
  end

  record v
    vim_did_enter: integer
    t_string: integer
  end

  record opt
    record Opt<T>
      get: function<T>(Opt<T>): T
    end

    diffopt: Opt<{string}>
    foldopen: Opt<{string}>
    shortmess: Opt<{string:boolean}>
    wrapscan: Opt<boolean>
  end

  record lsp
    record util
      close_preview_autocmd: function ({string}, number)
    end
  end

  loop: uv

  in_fast_event: function(): boolean

  list_extend: function<T>({T}, {T}, integer, integer): {T}
  list_slice: function<T>({T}, integer, integer): {T}

  record keymap
    record Options
      buffer: boolean|integer
      expr: boolean
    end
    set: function(string|{string}, string, string|function, Options)
  end

  record log
    record levels
      WARN: integer
      ERROR: integer
      INFO: integer
      DEBUG: integer
    end
  end
  notify: function(string, integer, table)
  pretty_print: function(any)

  split: function(string, string): {string}
  split: function(string, string, boolean): {string}

  gsplit: function(string, string, boolean): function(): string

  pesc: function(string): string

  record Regex
    userdata

    match_str: function(Regex, string): integer, integer
  end

  regex: function(string): Regex

  startswith: function(string, string): boolean
  endswith: function(string, string): boolean

  schedule_wrap: function(function()): function()
  schedule_wrap: function(function(...:any): any...): function(...:any): any...

  schedule: function(function)
  validate: function({string:{any}})
  trim: function(string): string

  enum ExtendBehavior
    'error'
    'keep'
    'force'
  end

  tbl_add_reverse_lookup: function<K,I>({K:I}): {I:K}
  tbl_contains: function(table, any): boolean
  tbl_count: function(table): integer
  tbl_deep_extend: function(ExtendBehavior, table, table, ...: table): table
  tbl_extend: function(ExtendBehavior, table, table, ...: table): table
  tbl_filter: function<T>((function(any): boolean), {T}): {T}
  tbl_isempty: function(table): boolean
  tbl_islist: function(table): boolean
  tbl_keys: function<K,V>({K:V}): {K}
  tbl_map: function(function, table): table

  record InspectOptions
    depth: number
    newline: string
    indent: string
    process: function
  end
  record inspect
    METATABLE: any
    KEY: any
    metamethod __call: function(inspect, any, InspectOptions): string
    metamethod __call: function(inspect, any): string
  end

  wait: function(number, function, number, boolean)

  record ui
    input: function({string:any}, function(string))
    record SelectOpts<T>
      prompt: string
      format_item: function(T): string
      kind: string
    end
    select: function<T>({T}, SelectOpts<T>, on_choice: function(T, idx: integer))
  end

  record VersionDetails
    api_compatible: integer
    api_level: integer
    api_prerelease: boolean
    major: integer
    minor: integer
    patch: integer
  end

  version: function(): VersionDetails

  record mpack
    encode: function(any): string
    decode: function(string): any
  end

  is_thread: function(): boolean

  record fs
    find: function(string|{string}, table): {string}
  end
end

return M
