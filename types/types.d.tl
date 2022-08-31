global _: any

global _TEST: boolean

global loadstring: function(string): (function(): any)

global unpack: function<T>({T}, number, number): T...

global getfenv: function(function): table

global record jit
  arch: string
  os: string
  version: string
  version_num: number
  off: function()
  off: function(function)
  on: function()
  status: function(): boolean
end

local record api
  record UserCmdParams
    args: string
    bang: boolean
    line1: integer
    line2: integer
    range: integer
    count: number
    reg: string
    mods: string

    record Mods
      browse       : boolean
      confirm      : boolean
      emsg_silent  : boolean
      hide         : boolean
      keepalt      : boolean
      keepjumps    : boolean
      keepmarks    : boolean
      keeppatterns : boolean
      lockmarks    : boolean
      noautocmd    : boolean
      noswapfile   : boolean
      sandbox      : boolean
      silent       : boolean
      tab          : integer
      verbose      : integer
      vertical     : boolean

      enum Split ''
        'aboveleft'
        'belowright'
        'topleft'
        'botright'
      end

      split : Split
    end
    smods: Mods
  end

  record UserCmdOpts
    nargs: string|integer
    range: boolean|string|integer
    count: boolean|integer
    addr: string
    bang: boolean
    bar: boolean
    register: boolean
    force: boolean
    complete: string|function(arglead: string, line: string): {string}
  end
  nvim_create_user_command: function(string, function(UserCmdParams), UserCmdOpts)
  nvim_buf_add_highlight: function(number, number, string, number, number, number): number
  nvim_buf_attach: function(number, boolean, {string:any}): boolean
  nvim_buf_call: function(number, function)
  nvim_buf_clear_highlight: function(number, number, number, number)
  nvim_buf_clear_namespace: function(number, number, number, number)
  nvim_buf_del_extmark: function(number, number, number): boolean
  nvim_buf_del_keymap: function(number, string, string)
  nvim_buf_del_var: function(number, string)
  nvim_buf_detach: function(number): boolean
  nvim_buf_get_changedtick: function(number): number
  nvim_buf_get_commands: function(number, {string:any}): {string:any}
  nvim_buf_get_extmark_by_id: function(number, number, number, table): {number}

  record GetExtmarOpts
    limit: integer
    details: boolean
  end

  nvim_buf_get_extmarks: function(
    buf: integer,
    ns: integer,
    start: integer | {integer, integer},
    eend: integer | {integer, integer},
    GetExtmarOpts
  ): {{integer, integer, integer}}

  nvim_buf_get_keymap: function(number, string): {{string:any}}
  nvim_buf_get_lines: function(number, number, number, boolean): {string}
  nvim_buf_get_mark: function(number, string): {number}
  nvim_buf_get_name: function(number): string
  nvim_buf_get_offset: function(number, number): number
  nvim_buf_get_option: function(number, string): any
  nvim_buf_get_var: function(number, string): any
  nvim_buf_get_virtual_text: function(number, number): any
  nvim_buf_is_loaded: function(number): boolean
  nvim_buf_is_valid: function(number): boolean
  nvim_buf_line_count: function(number): integer
  nvim_buf_set_extmark: function(integer, integer, integer, integer, {string:any}): integer
  nvim_buf_set_keymap: function(number, string, string, string, {string:any})
  nvim_buf_set_lines: function(number, number, number, boolean, {string})
  nvim_buf_set_name: function(number, string)
  nvim_buf_set_option: function(number, string, any)
  nvim_buf_set_var: function(number, string, any)
  nvim_buf_set_virtual_text: function(number, number, number, any, {string:any}): number
  nvim_call_atomic: function(any): any
  nvim_call_dict_function: function(any, string, any): any
  nvim_call_function: function(string, any): any
  nvim_command: function(string)
  nvim_create_buf: function(boolean, boolean): integer
  nvim_create_namespace: function(string): integer

  record AugroupOpts
    clear: boolean
  end

  nvim_create_augroup: function(string, AugroupOpts): integer

  record AutoCmdOpts
    callback: function()
    command: string
    group: string
    pattern: string|{string}
    once: boolean
    nested: boolean
    desc: string
    buffer: integer
  end

  nvim_create_autocmd: function(string|{string}, AutoCmdOpts): integer
  nvim_del_current_line: function()
  nvim_del_keymap: function(string, string)
  nvim_del_var: function(string)
  nvim_echo: function({{string}}, boolean, {string:any})
  nvim_err_write: function(string)
  nvim_err_writeln: function(string)
  nvim_eval: function(string): any
  nvim_exec: function(string, boolean): string
  nvim_exec_lua: function(string, any): any
  nvim_feedkeys: function(string, string, boolean)
  nvim_get_api_info: function(): any
  nvim_get_chan_info: function(number): {string:any}
  nvim_get_color_by_name: function(string): number
  nvim_get_color_map: function(): {string:any}
  nvim_get_commands: function({string:any}): {string:any}
  nvim_get_context: function({string:any}): {string:any}
  nvim_get_current_buf: function(): integer
  nvim_get_current_line: function(): string
  nvim_get_current_tabpage: function(): any
  nvim_get_current_win: function(): integer
  nvim_get_hl_by_id: function(number, boolean): {string:any}
  nvim_get_hl_by_name: function(string, boolean): {string:any}
  nvim_get_hl_id_by_name: function(string): number
  nvim_get_keymap: function(string): {{string:any}}
  nvim_get_mode: function(): {string:any}
  nvim_get_namespaces: function(): {string:any}
  nvim_get_option: function(string): any
  nvim_get_proc: function(number): any
  nvim_get_proc_children: function(number): any
  nvim_get_runtime_file: function(string, boolean): {string}
  nvim_get_var: function(string): any
  nvim_get_vvar: function(string): any
  nvim_input: function(string): number
  nvim_input_mouse: function(string, string, string, number, number, number)
  nvim_list_bufs: function(): {integer}
  nvim_list_chans: function(): any
  nvim_list_runtime_paths: function(): {string}
  nvim_list_tabpages: function(): {any}
  nvim_list_uis: function(): any
  nvim_list_wins: function(): {integer}
  nvim_load_context: function({string:any}): any
  nvim_open_win: function(number, boolean, {string:any}): integer
  nvim_out_write: function(string)
  nvim_parse_expression: function(string, string, boolean): {string:any}
  nvim_paste: function(string, boolean, number): boolean
  nvim_put: function({string}, string, boolean, boolean)
  nvim_replace_termcodes: function(string, boolean, boolean, boolean): string
  nvim_select_popupmenu_item: function(number, boolean, boolean, {string:any})
  nvim_set_client_info: function(string, {string:any}, string, {string:any}, {string:any})
  nvim_set_current_buf: function(number)
  nvim_set_current_dir: function(string)
  nvim_set_current_line: function(string)
  nvim_set_current_tabpage: function(any)
  nvim_set_current_win: function(number)
  nvim_set_decoration_provider: function(number, {string:function})
  nvim_set_hl: function(integer, string, {string:any})
  nvim_set_keymap: function(string, string, string, {string:any})
  nvim_set_option: function(string, any)
  nvim_set_var: function(string, any)
  nvim_set_vvar: function(string, any)
  nvim_strwidth: function(string): number
  nvim_subscribe: function(string)
  nvim_tabpage_del_var: function(any, string)
  nvim_tabpage_get_number: function(any): number
  nvim_tabpage_get_var: function(any, string): any
  nvim_tabpage_get_win: function(any): number
  nvim_tabpage_is_valid: function(any): boolean
  nvim_tabpage_list_wins: function(any): {number}
  nvim_tabpage_set_var: function(any, string, any)
  nvim_ui_attach: function(number, number, {string:any})
  nvim_ui_detach: function()
  nvim_ui_pum_set_bounds: function(number, number, number, number)
  nvim_ui_pum_set_height: function(number)
  nvim_ui_set_option: function(string, any)
  nvim_ui_try_resize: function(number, number)
  nvim_ui_try_resize_grid: function(number, number, number)
  nvim_unsubscribe: function(string)
  nvim_win_call: function<T>(number, (function(): T)): T
  nvim_win_close: function(number, boolean)
  nvim_win_del_var: function(number, string)
  nvim_win_get_buf: function(integer): integer
  nvim_win_get_config: function(number): {string:any}
  nvim_win_get_cursor: function(number): {integer}
  nvim_win_get_height: function(integer): integer
  nvim_win_get_number: function(number): number
  nvim_win_get_option: function(number, string): any
  nvim_win_get_position: function(number): {number}
  nvim_win_get_tabpage: function(number): any
  nvim_win_get_var: function(number, string): any
  nvim_win_get_width: function(integer): integer
  nvim_win_is_valid: function(number): boolean
  nvim_win_set_buf: function(number, number)
  nvim_win_set_config: function(number, {string:any})
  nvim_win_set_cursor: function(number, {number})
  nvim_win_set_height: function(number, number)
  nvim_win_set_option: function(number, string, any)
  nvim_win_set_var: function(number, string, any)
  nvim_win_set_width: function(number, number)

  nvim__buf_redraw_range: function(number, number, number)
end

global record vim
  api: api
  record fn
    iconv: function(string, string, string): string
    line: function(string): integer
    join: function({any}, string): string
    getpos: function(string): {integer}
    executable: function(string): integer
    expand: function(string): string
    foldclosed: function(integer): integer
    foldclosedend: function(integer): integer
    getcwd: function(): string
    input: function(string, string): string

    record QFItem
      bufnr: integer
      filename: string
      lnum: integer
      nr: integer
      text: string
      type: string
    end

    record QFWhat
      context: any
      efm: string
      id: integer
      idx: integer
      items: {QFItem}
      lines: {string}
      nr: integer
      quickfixtextfunc: string
      title: string
    end

    setqflist: function(list: {QFItem}, action: string, what: QFWhat)
    setloclist: function(nr: integer, list: {QFItem}, action: string, what: QFWhat)

    sign_unplace: function(string, {string:any})
    sign_place: function(number, string, string, string | number, {string:any})

    record SignPlaceItem
      buffer: integer
      group: string
      id: integer
      lnum: integer
      name: string
      priority: integer
    end
    sign_placelist: function({SignPlaceItem})
    sign_getdefined: function(string): table

    record SignPlacedInfo
      bufnr: integer
      record SignPlacedSigns
        id: integer
        name: string
        group: string
        lnum: integer
        priority: integer
      end
      signs: {SignPlacedSigns}
    end
    sign_getplaced: function(integer, table): {SignPlacedInfo}

    sign_define: function(string, table): number
    sign_undefine: function(string): number
    strdisplaywidth: function(string, integer): integer
    stridx: function(haystack: string, needle: string, start: integer): integer
    string: function(any): string
    tempname: function(): string
    type: function(any): integer
  end

  cmd: function(string): any

  deepcopy: function<T>(T): T

  defer_fn: function(function, integer): loop.Timer

  type DiffResult = {integer, integer, integer, integer}

  -- Assume result_type == 'indices'
  diff: function(string|{string}, string|{string}, table): {DiffResult}

  record o
    diffopt: string
    shortmess: string
    splitright: boolean
    updatetime: number
    wrapscan: boolean
  end

  record WinOption
    {WinOption}
    diff: boolean
  end

  wo: WinOption

  record BufOption
    {BufOption}
    fileformat: string
    fileencoding: string
    filetype: string
    modifiable: boolean
    modified: boolean

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
  end

  b: BufVar

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

  record loop
    cwd: function(): string
    record Timer
      userdata

      start: function(Timer, number, number, function): number
      stop: function(Timer): number
      close: function(Timer): number
      again: function(Timer): number
      set_repeat: function(Timer, number): number
      get_repeat: function(Timer): number
      get_due_in: function(Timer): number
    end
    hrtime: function(): number
    new_timer: function(): Timer | string
    timer_start: function(Timer, integer, integer, function()): integer | string

    new_fs_event: function()

    record FSPollObj
      userdata
      close: function(FSPollObj)
      start: function(FSPollObj, string, integer, function)
      stop: function(FSPollObj)
      getpath: function(FSPollObj): string
    end
    new_fs_poll: function(): FSPollObj | string

    record FsStatRet
      dev : number
      mode : number
      nlink : number
      uid : number
      gid : number
      rdev : number
      ino : number
      size : number
      blksize : number
      blocks : number
      flags : number
      gen : number
      record atime
        sec : number
        nsec : number
      end
      record mtime
        sec : number
        nsec : number
      end
      record ctime
        sec : number
        nsec : number
      end
      record birthtime
        sec : number
        nsec : number
      end
      type : string
    end

    fs_stat: function(string, function): FsStatRet

    fs_realpath: function(string): string

    new_tcp: function()

    sleep: function(integer)

    record Handle
      userdata

      close: function(Handle)
      is_closing: function(Handle): boolean | string
    end

    record Pipe
      userdata

      close: function(Pipe)
      is_closing: function(Pipe): boolean | string
      read_start: function(Pipe, err: any, data: string)
      read_stop: function(Pipe)
      write: function(Pipe, string, function())

      open: function(any)
    end

    record Process
      userdata

      close: function(Process)
    end

    record SpawnOpts
      stdio: {Pipe, Pipe, Pipe}
      args: {string}
      cwd: string
      env: {string}
    end

    spawn: function(string, SpawnOpts, function(integer, integer)): Process, integer

    read_start: function(Pipe, function)
    new_pipe: function(boolean): Pipe | string
    shutdown: function(any, function)
    close: function(any, function)

    record WorkCtx
      queue: function(WorkCtx, ...:any)
    end

    new_work: function(function, function): WorkCtx
  end

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
  tbl_deep_extend: function(ExtendBehavior, table, table, ...: table): table

  tbl_extend: function(ExtendBehavior, table, table, ...: table): table

  tbl_map: function(function, table): table

  tbl_keys: function(table): table

  tbl_filter: function((function(any): boolean), table): table

  tbl_count: function(table): integer

  tbl_isempty: function(table): boolean

  tbl_islist: function(table): boolean

  tbl_contains: function(table, any): boolean

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
end
