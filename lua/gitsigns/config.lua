--- @class (exact) Gitsigns.SchemaElem
--- @field type type|type[]|fun(x:any): boolean
--- @field type_help? string
--- @field default_change? fun(cb: fun()) Function to refresh the config value
--- @field deep_extend? boolean
--- @field default? any
--- @field deprecated? boolean
--- @field default_help? string
--- @field description string

--- @class (exact) Gitsigns.DiffthisOpts
---
--- Split window vertically. Default to `config.diff_opts.vertical`. If running
--- via command line, then shi is taken from the command modifiers.
--- @field vertical? boolean
--- @field split? 'aboveleft'|'belowright'|'topleft'|'botright'

--- @class (exact) Gitsigns.DiffOpts
--- @field algorithm 'myers'|'minimal'|'patience'|'histogram'
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
--- @field text string

--- @alias Gitsigns.SignType
--- | 'add'
--- | 'change'
--- | 'delete'
--- | 'topdelete'
--- | 'changedelete'
--- | 'untracked'

--- @alias Gitsigns.CurrentLineBlameFmtFun fun(user: string, info: table<string,any>): [string,string][]

--- @class (exact) Gitsigns.CurrentLineBlameOpts : Gitsigns.BlameOpts
--- @field virt_text? boolean
--- @field virt_text_pos? 'eol'|'overlay'|'right_align'
--- @field delay? integer
--- @field virt_text_priority? integer
--- @field use_focus? boolean

--- @class (exact) Gitsigns.BlameOpts
--- Ignore whitespace when running blame.
--- @field ignore_whitespace? boolean
--- Extra options passed to `git-blame`.
--- @field extra_opts? string[]

--- @class (exact) Gitsigns.Config
--- @field package _config table<string,any> config store
--- @field debug_mode boolean
--- @field diff_opts Gitsigns.DiffOpts
--- @field diffthis Gitsigns.DiffthisOpts
--- @field base? string
--- @field signs table<Gitsigns.SignType,Gitsigns.SignConfig>
--- @field signs_staged table<Gitsigns.SignType,Gitsigns.SignConfig>
--- @field signs_staged_enable boolean
--- @field count_chars table<string|integer,string>
--- @field signcolumn boolean
--- @field numhl boolean
--- @field linehl boolean
--- @field culhl boolean
--- @field show_deleted boolean
--- @field sign_priority integer
--- @field _on_attach_pre? fun(bufnr: integer, callback: fun(_: table))
--- @field on_attach? fun(bufnr: integer): boolean?
--- @field watch_gitdir { enable: boolean, follow_files: boolean }
--- @field max_file_length integer
--- @field update_debounce integer
--- @field status_formatter fun(_: table<string,any>): string
--- @field current_line_blame boolean
--- @field current_line_blame_formatter string|Gitsigns.CurrentLineBlameFmtFun
--- @field current_line_blame_formatter_nc string|Gitsigns.CurrentLineBlameFmtFun
--- @field current_line_blame_opts Gitsigns.CurrentLineBlameOpts
--- @field preview_config vim.api.keyset.win_config
--- @field auto_attach boolean
--- @field attach_to_untracked boolean
--- @field worktrees {toplevel: string, gitdir: string}[]
--- @field word_diff boolean
--- @field trouble boolean
--- @field gh boolean
--- -- Undocumented
--- @field _refresh_staged_on_update boolean
--- @field _threaded_diff boolean
--- @field _git_version string
--- @field _verbose boolean
--- @field _test_mode boolean
--- @field _new_sign_calc boolean
--- @field _update_lock boolean
--- @field _commit_maps boolean
--- @field _statuscolumn? boolean

--- @class Gitsigns.config
local M = {}

--- @alias Gitsigns.Config.SubscribersCb fun(old_val:any, new_val:any)
--- @type table<string, Gitsigns.Config.SubscribersCb[]>
local subscribers = {}

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
      r.algorithm = o:sub(#'algorithm:' + 1) --[[@as 'myers'|'minimal'|'patience'|'histogram']]
    elseif vim.startswith(o, 'linematch:') then
      r.linematch = tonumber(o:sub(('linematch:'):len() + 1))
    end
  end

  return r
end

--- @type Gitsigns.Config
M.config = setmetatable({ _config = {} }, {
  --- @param self Gitsigns.Config
  --- @param k string
  --- @param v any
  __newindex = function(self, k, v)
    local oldv = self._config[k]
    local field = M.schema[k]
    if not field then
      return
    end

    if field.deep_extend then
      self._config[k] = vim.tbl_deep_extend('force', resolve_default(field), v)
    else
      self._config[k] = v
    end

    if field.default_change then
      -- Reinvoke __newindex with the original value whenever the default
      -- value changes.
      field.default_change(function()
        --- @diagnostic disable-next-line: no-unknown
        self[k] = v
      end)
    end

    if oldv ~= nil and not vim.deep_equal(oldv, v) then
      for _, cb in ipairs(subscribers[k] or {}) do
        cb(oldv, v)
      end
    end
  end,
  --- @param self Gitsigns.Config
  --- @param k string
  --- @return any
  __index = function(self, k)
    -- Most values in the config should have the default (
    if self._config[k] == nil then
      local field = M.schema[k]
      if not field then
        return
      end

      self._config[k] = resolve_default(field)
    end

    return self._config[k]
  end,
})

local function warn(s, ...)
  vim.notify_once(s:format(...), vim.log.levels.WARN, { title = 'gitsigns' })
end

--- @param x Gitsigns.SignConfig
--- @return boolean
local function validate_signs(x)
  if type(x) ~= 'table' then
    return false
  end

  return true
end

--- @type table<string,Gitsigns.SchemaElem>
M.schema = {
  signs = {
    type_help = 'table',
    type = validate_signs,
    deep_extend = true,
    default = {
      add = { text = '┃' },
      change = { text = '┃' },
      delete = { text = '▁' },
      topdelete = { text = '▔' },
      changedelete = { text = '~' },
      untracked = { text = '┆' },
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
        • `GitSignsAddCul `(for signs when `config.culhl == true`)

      See |gitsigns-highlight-groups|.
    ]],
  },

  signs_staged = {
    type = 'table',
    deep_extend = true,
    default = {
      add = { text = '┃' },
      change = { text = '┃' },
      delete = { text = '▁' },
      topdelete = { text = '▔' },
      changedelete = { text = '~' },
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

  signs_staged_enable = {
    type = 'boolean',
    default = true,
    description = [[
    Show signs for staged hunks.

    When enabled the signs defined in |git-config-signs_staged| are used.
    ]],
  },

  worktrees = {
    type = 'table',
    default = {},
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

  culhl = {
    type = 'boolean',
    default = false,
    description = [[
      Enable/disable highlights for the sign column when the cursor is on
      the same line.

      When enabled the highlights defined in `signs.*.culhl` are used. If
      the highlight group does not exist, then it is automatically defined
      and linked to the corresponding highlight group in `signs.*.hl`.
    ]],
  },

  show_deleted = {
    type = 'boolean',
    deprecated = true,
    default = false,
    description = [[
      Show the old version of hunks inline in the buffer (via virtual lines).

      Note: Virtual lines currently use the highlight `GitSignsDeleteVirtLn`.
    ]],
  },

  diff_opts = {
    type = 'table',
    deep_extend = true,
    default_change = function(callback)
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

  diffthis = {
    type = 'table',
    default = {
      split = 'aboveleft',
    },
    description = [[
      Options for the `:Gitsigns diffthis` command.
    ]],
  },

  base = {
    type = 'string',
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

  auto_attach = {
    type = 'boolean',
    default = true,
    description = [[
      Automatically attach to files.
    ]],
  },

  attach_to_untracked = {
    type = 'boolean',
    default = false,
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
      use_focus = true,
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
        • use_focus: boolean
          Enable only when buffer is in focus
        • extra_opts: string[]
          Extra options passed to `git-blame`.
    ]],
  },

  current_line_blame_formatter = {
    type = { 'string', 'function' },
    default = ' <author>, <author_time:%R> - <summary> ',
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
          • `%%`  the character `%`
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

  gh = {
    type = 'boolean',
    default = false,
    description = [[
      Enable GitHub integration. This allows the following features:
      • `:Gitsigns blame_line` will show PR numbers (with a hyperlink)
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

  _new_sign_calc = {
    type = 'boolean',
    default = true,
    description = [[
      Use new sign calculation method
    ]],
  },

  _update_lock = {
    type = 'boolean',
    default = false,
    description = [[
      Acquire a lock when updating signs.
    ]],
  },

  _commit_maps = {
    type = 'boolean',
    default = false,
    description = [[
      Enable new mappings in commit buffers
    ]],
  },

  _statuscolumn = {
    type = 'boolean',
    default = false,
    description = [[
      Statuscolumn mode is enabled
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

--- Subscribe to a config change
--- @param k string|string[]
--- @param cb Gitsigns.Config.SubscribersCb
function M.subscribe(k, cb)
  if type(k) == 'string' then
    k = { k }
  end
  for _, v in ipairs(k) do
    subscribers[v] = subscribers[v] or {}
    table.insert(subscribers[v], cb)
  end
end

local nvim011 = vim.fn.has('nvim-0.11') == 1

--- @param k string
--- @param v any
--- @param ty type|fun(v:any):boolean
local function validate(k, v, ty)
  if nvim011 then
    --- @diagnostic disable-next-line: redundant-parameter,param-type-mismatch
    vim.validate(k, v, ty)
  else
    vim.validate({ [k] = { v, ty } })
  end
end

--- @param user_config table
function M.build(user_config)
  --- @cast user_config table<string,any>

  local config = M.config --[[@as table<string,any>]]

  -- Check deprecated config options
  for k, v in pairs(user_config) do
    local s = M.schema[k]
    if not s then
      warn("gitsigns: Ignoring invalid configuration field '%s'", k)
    else
      local ty = s.type
      if type(ty) == 'string' or type(ty) == 'function' then
        --- EmmyLuaLs/emmylua-analyzer-rust#696
        --- @diagnostic disable-next-line: param-type-not-match, param-type-mismatch
        validate(k, v, ty)
      end
      if s.deprecated then
        warn('%s is now deprecated; ignoring', k)
      end
      config[k] = v
    end
  end
end

return M
