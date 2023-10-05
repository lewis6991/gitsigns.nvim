--- @class (exact) Gitsigns.SchemaElem
--- @field type string|string[]
--- @field refresh? fun(cb: fun()) Function to refresh the config value
--- @field deep_extend? boolean
--- @field default any
--- @field deprecated? boolean|{new_field:string,message:string,hard:boolean}
--- @field default_help? string
--- @field description string

--- @class (exact) Gitsigns.DiffOpts
--- @field algorithm string
--- @field internal boolean
--- @field indent_heuristic boolean
--- @field vertical boolean
--- @field linematch? integer
--- @field ignore_whitespace_change? true
--- @field ignore_whitespace? true
--- @field ignore_whitespace_change_at_eol? true
--- @field ignore_blank_lines? true

--- @class (exact) Gitsigns.SignConfig
--- @field show_count boolean
--- @field hl string
--- @field text string
--- @field numhl string
--- @field linehl string

--- @alias Gitsigns.SignType
--- | 'add'
--- | 'change'
--- | 'delete'
--- | 'topdelete'
--- | 'changedelete'
--- | 'untracked'

--- @class (exact) Gitsigns.CurrentLineBlameFmtOpts
--- @field relative_time boolean

--- @alias Gitsigns.CurrentLineBlameFmtFun fun(user: string, info: table<string,any>, opts: Gitsigns.CurrentLineBlameFmtOpts): {[1]:string,[2]:string}[]

--- @class (exact) Gitsigns.CurrentLineBlameOpts
--- @field virt_text boolean
--- @field virt_text_pos 'eol'|'overlay'|'right_align'
--- @field delay integer
--- @field ignore_whitespace boolean
--- @field virt_text_priority integer

--- @class (exact) Gitsigns.Config
--- @field debug_mode boolean
--- @field diff_opts Gitsigns.DiffOpts
--- @field base? string
--- @field signs table<Gitsigns.SignType,Gitsigns.SignConfig>
--- @field _signs_staged table<Gitsigns.SignType,Gitsigns.SignConfig>
--- @field _signs_staged_enable boolean
--- @field count_chars table<string|integer,string>
--- @field signcolumn boolean
--- @field numhl boolean
--- @field linehl boolean
--- @field show_deleted boolean
--- @field sign_priority integer
--- @field _on_attach_pre fun(bufnr: integer, callback: fun(_: table))
--- @field on_attach fun(bufnr: integer)
--- @field watch_gitdir { enable: boolean, follow_files: boolean }
--- @field max_file_length integer
--- @field update_debounce integer
--- @field status_formatter fun(_: table<string,any>): string
--- @field current_line_blame boolean
--- @field current_line_blame_formatter_opts { relative_time: boolean }
--- @field current_line_blame_formatter string|Gitsigns.CurrentLineBlameFmtFun
--- @field current_line_blame_formatter_nc string|Gitsigns.CurrentLineBlameFmtFun
--- @field current_line_blame_opts Gitsigns.CurrentLineBlameOpts
--- @field preview_config table<string,any>
--- @field attach_to_untracked boolean
--- @field yadm { enable: boolean }
--- @field worktrees {toplevel: string, gitdir: string}[]
--- @field word_diff boolean
--- @field trouble boolean
--- -- Undocumented
--- @field _refresh_staged_on_update boolean
--- @field _threaded_diff boolean
--- @field _inline2 boolean
--- @field _extmark_signs boolean
--- @field _git_version string
--- @field _verbose boolean
--- @field _test_mode boolean

local M = {
  Config = {
    DiffOpts = {},
    SignConfig = {},
    watch_gitdir = {},
    current_line_blame_formatter_opts = {},
    current_line_blame_opts = {},
    yadm = {},
    Worktree = {},
  },
}

--- @param v Gitsigns.SchemaElem
--- @return any
local function resolve_default(v)
  if type(v.default) == 'function' and v.type ~= 'function' then
    return v.default()
  else
    return v.default
  end
end

--- @return Gitsigns.DiffOpts
local function parse_diffopt()
  --- @type Gitsigns.DiffOpts
  local r = {
    algorithm = 'myers',
    internal = false,
    indent_heuristic = false,
    vertical = true,
  }

  local optmap = {
    ['indent-heuristic'] = 'indent_heuristic',
    internal = 'internal',
    iwhite = 'ignore_whitespace_change',
    iblank = 'ignore_blank_lines',
    iwhiteeol = 'ignore_whitespace_change_at_eol',
    iwhiteall = 'ignore_whitespace',
  }

  local diffopt = vim.opt.diffopt:get() --[[@as string[] ]]
  for _, o in ipairs(diffopt) do
    if optmap[o] then
      r[optmap[o]] = true
    elseif o == 'horizontal' then
      r.vertical = false
    elseif vim.startswith(o, 'algorithm:') then
      r.algorithm = string.sub(o, ('algorithm:'):len() + 1)
    elseif vim.startswith(o, 'linematch:') then
      r.linematch = tonumber(string.sub(o, ('linematch:'):len() + 1))
    end
  end

  return r
end

--- @type Gitsigns.Config
M.config = setmetatable({}, {
  __index = function(t, k)
    if rawget(t, k) == nil then
      local field = M.schema[k]
      if not field then
        return
      end

      rawset(t, k, resolve_default(field))

      if field.refresh then
        field.refresh(function()
          rawset(t, k, resolve_default(field))
        end)
      end
    end

    return rawget(t, k)
  end,
})

--- @type table<string,Gitsigns.SchemaElem>
M.schema = {
  signs = {
    type = 'table',
    deep_extend = true,
    default = {
      add = { hl = 'GitSignsAdd', text = '┃', numhl = 'GitSignsAddNr', linehl = 'GitSignsAddLn' },
      change = {
        hl = 'GitSignsChange',
        text = '┃',
        numhl = 'GitSignsChangeNr',
        linehl = 'GitSignsChangeLn',
      },
      delete = {
        hl = 'GitSignsDelete',
        text = '▁',
        numhl = 'GitSignsDeleteNr',
        linehl = 'GitSignsDeleteLn',
      },
      topdelete = {
        hl = 'GitSignsTopdelete',
        text = '▔',
        numhl = 'GitSignsTopdeleteNr',
        linehl = 'GitSignsTopdeleteLn',
      },
      changedelete = {
        hl = 'GitSignsChangedelete',
        text = '~',
        numhl = 'GitSignsChangedeleteNr',
        linehl = 'GitSignsChangedeleteLn',
      },
      untracked = {
        hl = 'GitSignsUntracked',
        text = '┆',
        numhl = 'GitSignsUntrackedNr',
        linehl = 'GitSignsUntrackedLn',
      },
    },
    default_help = [[{
      add          = { text = '┃' },
      change       = { text = '┃' },
      delete       = { text = '▁' },
      topdelete    = { text = '▔' },
      changedelete = { text = '~' },
      untracked    = { text = '┆' },
    }]],
    description = [[
      Configuration for signs:
        • `text` specifies the character to use for the sign.
        • `show_count` to enable showing count of hunk, e.g. number of deleted
          lines.

      The highlights `GitSigns[kind][type]` is used for each kind of sign. E.g.
      'add' signs uses the highlights:
        • `GitSignsAdd`   (for normal text signs)
        • `GitSignsAddNr` (for signs when `config.numhl == true`)
        • `GitSignsAddLn `(for signs when `config.linehl == true`)

      See |gitsigns-highlight-groups|.
    ]],
  },

  _signs_staged = {
    type = 'table',
    deep_extend = true,
    default = {
      add = {
        hl = 'GitSignsStagedAdd',
        text = '┃',
        numhl = 'GitSignsStagedAddNr',
        linehl = 'GitSignsStagedAddLn',
      },
      change = {
        hl = 'GitSignsStagedChange',
        text = '┃',
        numhl = 'GitSignsStagedChangeNr',
        linehl = 'GitSignsStagedChangeLn',
      },
      delete = {
        hl = 'GitSignsStagedDelete',
        text = '▁',
        numhl = 'GitSignsStagedDeleteNr',
        linehl = 'GitSignsStagedDeleteLn',
      },
      topdelete = {
        hl = 'GitSignsStagedTopdelete',
        text = '▔',
        numhl = 'GitSignsStagedTopdeleteNr',
        linehl = 'GitSignsStagedTopdeleteLn',
      },
      changedelete = {
        hl = 'GitSignsStagedChangedelete',
        text = '~',
        numhl = 'GitSignsStagedChangedeleteNr',
        linehl = 'GitSignsStagedChangedeleteLn',
      },
    },
    default_help = [[{
      add          = { text = '┃' },
      change       = { text = '┃' },
      delete       = { text = '▁' },
      topdelete    = { text = '▔' },
      changedelete = { text = '~' },
    }]],
    description = [[
    Configuration for signs of staged hunks.

    See |gitsigns-config-signs|.
    ]],
  },

  _signs_staged_enable = {
    type = 'boolean',
    default = false,
    description = [[
    Show signs for staged hunks.

    When enabled the signs defined in |git-config-signs_staged|` are used.
    ]],
  },

  worktrees = {
    type = 'table',
    default = nil,
    description = [[
      Detached working trees.

      Array of tables with the keys `gitdir` and `toplevel`.

      If normal attaching fails, then each entry in the table is attempted
      with the work tree details set.

      Example: >lua
        worktrees = {
          {
            toplevel = vim.env.HOME,
            gitdir = vim.env.HOME .. '/projects/dotfiles/.git'
          }
        }
    ]],
  },

  _on_attach_pre = {
    type = 'function',
    default = nil,
    description = [[
      Asynchronous hook called before attaching to a buffer. Mainly used to
      configure detached worktrees.

      This callback must call its callback argument. The callback argument can
      accept an optional table argument with the keys: 'gitdir' and 'toplevel'.

      Example: >lua
      on_attach_pre = function(bufnr, callback)
        ...
        callback {
          gitdir = ...,
          toplevel = ...
        }
      end
      <
    ]],
  },

  on_attach = {
    type = 'function',
    default = nil,
    description = [[
      Callback called when attaching to a buffer. Mainly used to setup keymaps.
      The buffer number is passed as the first argument.

      This callback can return `false` to prevent attaching to the buffer.

      Example: >lua
        on_attach = function(bufnr)
          if vim.api.nvim_buf_get_name(bufnr):match(<PATTERN>) then
            -- Don't attach to specific buffers whose name matches a pattern
            return false
          end

          -- Setup keymaps
          vim.api.nvim_buf_set_keymap(bufnr, 'n', 'hs', '<cmd>lua require"gitsigns".stage_hunk()<CR>', {})
          ... -- More keymaps
        end
<
    ]],
  },

  watch_gitdir = {
    type = 'table',
    deep_extend = true,
    default = {
      enable = true,
      follow_files = true,
    },
    description = [[
      When opening a file, a libuv watcher is placed on the respective
      `.git` directory to detect when changes happen to use as a trigger to
      update signs.

      Fields: ~
        • `enable`:
            Whether the watcher is enabled.

        • `follow_files`:
            If a file is moved with `git mv`, switch the buffer to the new location.
    ]],
  },

  sign_priority = {
    type = 'number',
    default = 6,
    description = [[
      Priority to use for signs.
    ]],
  },

  signcolumn = {
    type = 'boolean',
    default = true,
    description = [[
      Enable/disable symbols in the sign column.

      When enabled the highlights defined in `signs.*.hl` and symbols defined
      in `signs.*.text` are used.
    ]],
  },

  numhl = {
    type = 'boolean',
    default = false,
    description = [[
      Enable/disable line number highlights.

      When enabled the highlights defined in `signs.*.numhl` are used. If
      the highlight group does not exist, then it is automatically defined
      and linked to the corresponding highlight group in `signs.*.hl`.
    ]],
  },

  linehl = {
    type = 'boolean',
    default = false,
    description = [[
      Enable/disable line highlights.

      When enabled the highlights defined in `signs.*.linehl` are used. If
      the highlight group does not exist, then it is automatically defined
      and linked to the corresponding highlight group in `signs.*.hl`.
    ]],
  },

  show_deleted = {
    type = 'boolean',
    default = false,
    description = [[
      Show the old version of hunks inline in the buffer (via virtual lines).

      Note: Virtual lines currently use the highlight `GitSignsDeleteVirtLn`.
    ]],
  },

  diff_opts = {
    type = 'table',
    deep_extend = true,
    refresh = function(callback)
      vim.api.nvim_create_autocmd('OptionSet', {
        group = vim.api.nvim_create_augroup('gitsigns.config.diff_opts', {}),
        pattern = 'diffopt',
        callback = callback,
      })
    end,
    default = parse_diffopt,
    default_help = "derived from 'diffopt'",
    description = [[
      Diff options. If the default value is used, then changes to 'diffopt' are
      automatically applied.

      Fields: ~
        • algorithm: string
            Diff algorithm to use. Values:
            • "myers"      the default algorithm
            • "minimal"    spend extra time to generate the
                           smallest possible diff
            • "patience"   patience diff algorithm
            • "histogram"  histogram diff algorithm
        • internal: boolean
            Use Neovim's built in xdiff library for running diffs.
        • indent_heuristic: boolean
            Use the indent heuristic for the internal
            diff library.
        • vertical: boolean
            Start diff mode with vertical splits.
        • linematch: integer
            Enable second-stage diff on hunks to align lines.
            Requires `internal=true`.
       • ignore_blank_lines: boolean
            Ignore changes where lines are blank.
       • ignore_whitespace_change: boolean
            Ignore changes in amount of white space.
            It should ignore adding trailing white space,
            but not leading white space.
       • ignore_whitespace: boolean
           Ignore all white space changes.
       • ignore_whitespace_change_at_eol: boolean
            Ignore white space changes at end of line.
    ]],
  },

  base = {
    type = 'string',
    default = nil,
    default_help = 'index',
    description = [[
      The object/revision to diff against.
      See |gitsigns-revision|.
    ]],
  },

  count_chars = {
    type = 'table',
    default = {
      [1] = '1', -- '₁',
      [2] = '2', -- '₂',
      [3] = '3', -- '₃',
      [4] = '4', -- '₄',
      [5] = '5', -- '₅',
      [6] = '6', -- '₆',
      [7] = '7', -- '₇',
      [8] = '8', -- '₈',
      [9] = '9', -- '₉',
      ['+'] = '>', -- '₊',
    },
    description = [[
      The count characters used when `signs.*.show_count` is enabled. The
      `+` entry is used as a fallback. With the default, any count outside
      of 1-9 uses the `>` character in the sign.

      Possible use cases for this field:
        • to specify unicode characters for the counts instead of 1-9.
        • to define characters to be used for counts greater than 9.
    ]],
  },

  status_formatter = {
    type = 'function',
    --- @param status Gitsigns.StatusObj
    --- @return string
    default = function(status)
      local added, changed, removed = status.added, status.changed, status.removed
      local status_txt = {}
      if added and added > 0 then
        table.insert(status_txt, '+' .. added)
      end
      if changed and changed > 0 then
        table.insert(status_txt, '~' .. changed)
      end
      if removed and removed > 0 then
        table.insert(status_txt, '-' .. removed)
      end
      return table.concat(status_txt, ' ')
    end,
    default_help = [[function(status)
      local added, changed, removed = status.added, status.changed, status.removed
      local status_txt = {}
      if added   and added   > 0 then table.insert(status_txt, '+'..added  ) end
      if changed and changed > 0 then table.insert(status_txt, '~'..changed) end
      if removed and removed > 0 then table.insert(status_txt, '-'..removed) end
      return table.concat(status_txt, ' ')
    end]],
    description = [[
      Function used to format `b:gitsigns_status`.
    ]],
  },

  max_file_length = {
    type = 'number',
    default = 40000,
    description = [[
      Max file length (in lines) to attach to.
    ]],
  },

  preview_config = {
    type = 'table',
    deep_extend = true,
    default = {
      border = 'single',
      style = 'minimal',
      relative = 'cursor',
      row = 0,
      col = 1,
    },
    description = [[
      Option overrides for the Gitsigns preview window. Table is passed directly
      to `nvim_open_win`.
    ]],
  },

  attach_to_untracked = {
    type = 'boolean',
    default = true,
    description = [[
      Attach to untracked files.
    ]],
  },

  update_debounce = {
    type = 'number',
    default = 100,
    description = [[
      Debounce time for updates (in milliseconds).
    ]],
  },

  current_line_blame = {
    type = 'boolean',
    default = false,
    description = [[
      Adds an unobtrusive and customisable blame annotation at the end of
      the current line.

      The highlight group used for the text is `GitSignsCurrentLineBlame`.
    ]],
  },

  current_line_blame_opts = {
    type = 'table',
    deep_extend = true,
    default = {
      virt_text = true,
      virt_text_pos = 'eol',
      virt_text_priority = 100,
      delay = 1000,
    },
    description = [[
      Options for the current line blame annotation.

      Fields: ~
        • virt_text: boolean
          Whether to show a virtual text blame annotation.
        • virt_text_pos: string
          Blame annotation position. Available values:
            `eol`         Right after eol character.
            `overlay`     Display over the specified column, without
                          shifting the underlying text.
            `right_align` Display right aligned in the window.
        • delay: integer
          Sets the delay (in milliseconds) before blame virtual text is
          displayed.
        • ignore_whitespace: boolean
          Ignore whitespace when running blame.
        • virt_text_priority: integer
          Priority of virtual text.
    ]],
  },

  current_line_blame_formatter_opts = {
    type = 'table',
    deep_extend = true,
    deprecated = true,
    default = {
      relative_time = false,
    },
    description = [[
      Options for the current line blame annotation formatter.

      Fields: ~
        • relative_time: boolean
    ]],
  },

  current_line_blame_formatter = {
    type = { 'string', 'function' },
    default = ' <author>, <author_time> - <summary> ',
    description = [[
      String or function used to format the virtual text of
      |gitsigns-config-current_line_blame|.

      When a string, accepts the following format specifiers:

          • `<abbrev_sha>`
          • `<orig_lnum>`
          • `<final_lnum>`
          • `<author>`
          • `<author_mail>`
          • `<author_time>` or `<author_time:FORMAT>`
          • `<author_tz>`
          • `<committer>`
          • `<committer_mail>`
          • `<committer_time>` or `<committer_time:FORMAT>`
          • `<committer_tz>`
          • `<summary>`
          • `<previous>`
          • `<filename>`

        For `<author_time:FORMAT>` and `<committer_time:FORMAT>`, `FORMAT` can
        be any valid date format that is accepted by `os.date()` with the
        addition of `%R` (defaults to `%Y-%m-%d`):

          • `%a`  abbreviated weekday name (e.g., Wed)
          • `%A`  full weekday name (e.g., Wednesday)
          • `%b`  abbreviated month name (e.g., Sep)
          • `%B`  full month name (e.g., September)
          • `%c`  date and time (e.g., 09/16/98 23:48:10)
          • `%d`  day of the month (16) [01-31]
          • `%H`  hour, using a 24-hour clock (23) [00-23]
          • `%I`  hour, using a 12-hour clock (11) [01-12]
          • `%M`  minute (48) [00-59]
          • `%m`  month (09) [01-12]
          • `%p`  either "am" or "pm" (pm)
          • `%S`  second (10) [00-61]
          • `%w`  weekday (3) [0-6 = Sunday-Saturday]
          • `%x`  date (e.g., 09/16/98)
          • `%X`  time (e.g., 23:48:10)
          • `%Y`  full year (1998)
          • `%y`  two-digit year (98) [00-99]
          • `%%`  the character `%´
          • `%R`  relative (e.g., 4 months ago)

      When a function:
        Parameters: ~
          {name}       Git user name returned from `git config user.name` .
          {blame_info} Table with the following keys:
                         • `abbrev_sha`: string
                         • `orig_lnum`: integer
                         • `final_lnum`: integer
                         • `author`: string
                         • `author_mail`: string
                         • `author_time`: integer
                         • `author_tz`: string
                         • `committer`: string
                         • `committer_mail`: string
                         • `committer_time`: integer
                         • `committer_tz`: string
                         • `summary`: string
                         • `previous`: string
                         • `filename`: string
                         • `boundary`: true?

                       Note that the keys map onto the output of:
                         `git blame --line-porcelain`

          {opts}       Passed directly from
                       |gitsigns-config-current_line_blame_formatter_opts|.

        Return: ~
          The result of this function is passed directly to the `opts.virt_text`
          field of |nvim_buf_set_extmark| and thus must be a list of
          [text, highlight] tuples.
    ]],
  },

  current_line_blame_formatter_nc = {
    type = { 'string', 'function' },
    default = ' <author>',
    description = [[
      String or function used to format the virtual text of
      |gitsigns-config-current_line_blame| for lines that aren't committed.

      See |gitsigns-config-current_line_blame_formatter| for more information.
    ]],
  },

  trouble = {
    type = 'boolean',
    default = function()
      local has_trouble = pcall(require, 'trouble')
      return has_trouble
    end,
    default_help = 'true if installed',
    description = [[
      When using setqflist() or setloclist(), open Trouble instead of the
      quickfix/location list window.
    ]],
  },

  yadm = {
    type = 'table',
    default = { enable = false },
    description = [[
      yadm configuration.
    ]],
  },

  _git_version = {
    type = 'string',
    default = 'auto',
    description = [[
      Version of git available. Set to 'auto' to automatically detect.
    ]],
  },

  _verbose = {
    type = 'boolean',
    default = false,
    description = [[
      More verbose debug message. Requires debug_mode=true.
    ]],
  },

  _test_mode = {
    description = 'Enable test mode',
    type = 'boolean',
    default = false,
  },

  word_diff = {
    type = 'boolean',
    default = false,
    description = [[
      Highlight intra-line word differences in the buffer.
      Requires `config.diff_opts.internal = true` .

      Uses the highlights:
        • For word diff in previews:
          • `GitSignsAddInline`
          • `GitSignsChangeInline`
          • `GitSignsDeleteInline`
        • For word diff in buffer:
          • `GitSignsAddLnInline`
          • `GitSignsChangeLnInline`
          • `GitSignsDeleteLnInline`
        • For word diff in virtual lines (e.g. show_deleted):
          • `GitSignsAddVirtLnInline`
          • `GitSignsChangeVirtLnInline`
          • `GitSignsDeleteVirtLnInline`
    ]],
  },

  _refresh_staged_on_update = {
    type = 'boolean',
    default = false,
    description = [[
      Always refresh the staged file on each update. Disabling this will cause
      the staged file to only be refreshed when an update to the index is
      detected.
    ]],
  },

  _threaded_diff = {
    type = 'boolean',
    default = true,
    description = [[
      Run diffs on a separate thread
    ]],
  },

  _inline2 = {
    type = 'boolean',
    default = false,
    description = [[
      Enable enhanced version of preview_hunk_inline()
    ]],
  },

  _extmark_signs = {
    type = 'boolean',
    default = true,
    description = [[
      Use extmarks for placing signs.
    ]],
  },

  debug_mode = {
    type = 'boolean',
    default = false,
    description = [[
      Enables debug logging and makes the following functions
      available: `dump_cache`, `debug_messages`, `clear_debug`.
    ]],
  },
}

local function warn(s, ...)
  vim.notify(s:format(...), vim.log.levels.WARN, { title = 'gitsigns' })
end

--- @param config Gitsigns.Config
local function validate_config(config)
  --- @diagnostic disable-next-line:no-unknown
  for k, v in pairs(config) do
    local kschema = M.schema[k]
    if kschema == nil then
      warn("gitsigns: Ignoring invalid configuration field '%s'", k)
    elseif kschema.type then
      if type(kschema.type) == 'string' then
        vim.validate({
          [k] = { v, kschema.type },
        })
      end
    end
  end
end

--- @param cfg table<any, any>
local function handle_deprecated(cfg)
  for k, v in pairs(M.schema) do
    local dep = v.deprecated
    if dep and cfg[k] ~= nil then
      if type(dep) == 'table' then
        if dep.new_field then
          local opts_key, field = dep.new_field:match('(.*)%.(.*)')
          if opts_key and field then
            -- Field moved to an options table
            local opts = (cfg[opts_key] or {}) --[[@as table<any,any>]]
            opts[field] = cfg[k]
            cfg[opts_key] = opts
          else
            -- Field renamed
            cfg[dep.new_field] = cfg[k]
          end
        end

        if dep.hard then
          if dep.message then
            warn(dep.message)
          elseif dep.new_field then
            warn('%s is now deprecated, please use %s', k, dep.new_field)
          else
            warn('%s is now deprecated; ignoring', k)
          end
        end
      end
    end
  end
end

--- @param k string
--- @param v Gitsigns.SchemaElem
--- @param user_val any
local function build_field(k, v, user_val)
  local config = M.config --[[@as table<string,any>]]

  if v.deep_extend then
    local d = resolve_default(v)
    config[k] = vim.tbl_deep_extend('force', d, user_val)
  else
    config[k] = user_val
  end
end

--- @param user_config Gitsigns.Config|nil
function M.build(user_config)
  user_config = user_config or {}

  handle_deprecated(user_config)

  validate_config(user_config)

  for k, v in pairs(M.schema) do
    if user_config[k] ~= nil then
      build_field(k, v, user_config[k])
      if v.refresh then
        v.refresh(function()
          build_field(k, v, user_config[k])
        end)
      end
    end
  end
end

return M
