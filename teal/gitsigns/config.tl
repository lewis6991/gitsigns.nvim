local record SchemaElem
  type: string
  deep_extend: boolean
  default: any
  default_help: string
  description: string
end

local record M
  record Config
    debug_mode: boolean
    diff_algorithm: string

    record SignsConfig
      show_count: boolean
      hl: string
      text: string
      numhl: string
      linehl: string
      keymaps: {string:string}
    end
    signs: {string: SignsConfig}

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
    status_formatter: function({string:any}): string
    current_line_blame: boolean
    current_line_blame_formatter: function(string, {string:any}): string
    use_internal_diff: boolean
    use_decoration_api: boolean

    -- Undocumented
    _refresh_staged_on_update: boolean

    _git_version: string
  end

  schema: {string:SchemaElem}
end

M.schema = {
  signs = {
    type = 'table',
    deep_extend = true,
    default = [[{
      add          = {hl = 'GitSignsAdd'   , text = '│', numhl='GitSignsAddNr'   , linehl='GitSignsAddLn'    },
      change       = {hl = 'GitSignsChange', text = '│', numhl='GitSignsChangeNr', linehl='GitSignsChangeLn' },
      delete       = {hl = 'GitSignsDelete', text = '_', numhl='GitSignsDeleteNr', linehl='GitSignsDeleteLn' },
      topdelete    = {hl = 'GitSignsDelete', text = '‾', numhl='GitSignsDeleteNr', linehl='GitSignsDeleteLn' },
      changedelete = {hl = 'GitSignsChange', text = '~', numhl='GitSignsChangeNr', linehl='GitSignsChangeLn' },
    }]],
    description = [[
        Configuration for signs:
          • `hl` specifies the highlight group to use for the sign.
          • `text` specifies the character to use for the sign.
          • `numhl` specifies the highlight group to use for the number column
            (see |gitsigns-config.numhl|).
          • `linehl` specifies the highlight group to use for the line
            (see |gitsigns-config.linehl|).
          • `show_count` to enable showing count of hunk, e.g. number of deleted
            lines.

        Note if `hl`, `numhl` or `linehl` use a `GitSigns*` highlight and it is
        not defined, it will be automatically derived by searching for other
        defined highlights in the following order:
          • `GitGutter*`
          • `Signify*`
          • `Diff*`

        For example if `signs.add.hl = GitSignsAdd` and `GitSignsAdd` is not
        defined but `GitGutterAdd` is defined, then `GitSignsAdd` will be linked
        to `GitGutterAdd`.

    ]]
  },

  keymaps = {
    type = 'table',
    default = [[{
      -- Default keymap options
      noremap = true,
      buffer = true,

      ['n ]c'] = { expr = true, "&diff ? ']c' : '<cmd>lua require\"gitsigns\".next_hunk()<CR>'"},
      ['n [c'] = { expr = true, "&diff ? '[c' : '<cmd>lua require\"gitsigns\".prev_hunk()<CR>'"},

      ['n <leader>hs'] = '<cmd>lua require"gitsigns".stage_hunk()<CR>',
      ['n <leader>hu'] = '<cmd>lua require"gitsigns".undo_stage_hunk()<CR>',
      ['n <leader>hr'] = '<cmd>lua require"gitsigns".reset_hunk()<CR>',
      ['n <leader>hR'] = '<cmd>lua require"gitsigns".reset_buffer()<CR>',
      ['n <leader>hp'] = '<cmd>lua require"gitsigns".preview_hunk()<CR>',
      ['n <leader>hb'] = '<cmd>lua require"gitsigns".blame_line()<CR>',

      ['o ih'] = ':<C-U>lua require"gitsigns".select_hunk()<CR>',
      ['x ih'] = ':<C-U>lua require"gitsigns".select_hunk()<CR>'
    }]],
    description = [[
        Keymaps to set up when attaching to a buffer.

        Each key in the table defines the mode and key (whitespace delimited)
        for the mapping and the value defines what the key maps to. The value
        can be a table which can contain keys matching the options defined in
        |map-arguments| which are: `expr`, `noremap`, `nowait`, `script`,
        `silent`, `unique` and `buffer`.  These options can also be used in
        the top level of the table to define default options for all mappings.
    ]]
  },

  watch_index = {
    type = 'table',
    default = [[{ interval = 1000 }]],
    description = [[
        When opening a file, a libuv watcher is placed on the respective
        `.git/index` file to detect when changes happen to use as a trigger to
        update signs.
    ]]
  },

  sign_priority = {
    type = 'number',
    default = 6,
    description = [[
        Priority to use for signs.
    ]]
  },

  signcolumn = {
    type = 'boolean',
    default = true,
    description = [[
        Enable/disable symbols in the sign column.

        When enabled the highlights defined in `signs.*.hl` and symbols defined
        in `signs.*.text` are used.
    ]]
  },

  numhl = {
    type = 'boolean',
    default = false,
    description = [[
        Enable/disable line number highlights.

        When enabled the highlights defined in `signs.*.numhl` are used. If
        the highlight group does not exist, then it is automatically defined
        and linked to the corresponding highlight group in `signs.*.hl`.
    ]]
  },

  linehl = {
    type = 'boolean',
    default = false,
    description = [[
        Enable/disable line highlights.

        When enabled the highlights defined in `signs.*.linehl` are used. If
        the highlight group does not exist, then it is automatically defined
        and linked to the corresponding highlight group in `signs.*.hl`.
    ]]
  },

  diff_algorithm = {
    type = 'string',

    -- Get algorithm from 'diffopt'
    default = [[function()
      local algo = 'myers'
      for o in vim.gsplit(vim.o.diffopt, ',') do
        if vim.startswith(o, 'algorithm:') then
          algo = string.sub(o, 11)
        end
      end
      return algo
    end]],
    default_help = "taken from 'diffopt'",
    description = [[
        Diff algorithm to pass to `git diff` .
    ]]
  },

  count_chars = {
    type = 'table',
    default = {
      [1]   = '1', -- '₁',
      [2]   = '2', -- '₂',
      [3]   = '3', -- '₃',
      [4]   = '4', -- '₄',
      [5]   = '5', -- '₅',
      [6]   = '6', -- '₆',
      [7]   = '7', -- '₇',
      [8]   = '8', -- '₈',
      [9]   = '9', -- '₉',
      ['+'] = '>', -- '₊',
    },
    description = [[
        The count characters used when `signs.*.show_count` is enabled. The
        `+` entry is used as a fallback. With the default, any count outside
        of 1-9 uses the `>` character in the sign.

        Possible use cases for this field:
          • to specify unicode characters for the counts instead of 1-9.
          • to define characters to be used for counts greater than 9.
    ]]
  },

  status_formatter = {
    type = 'function',
    default = [[function(status)
      local added, changed, removed = status.added, status.changed, status.removed
      local status_txt = {}
      if added   and added   > 0 then table.insert(status_txt, '+'..added  ) end
      if changed and changed > 0 then table.insert(status_txt, '~'..changed) end
      if removed and removed > 0 then table.insert(status_txt, '-'..removed) end
      return table.concat(status_txt, ' ')
    end]],
    description = [[
        Function used to format `b:gitsigns_status`.
    ]]
  },

  max_file_length = {
    type = 'number',
    default = 40000,
    description = [[
      Max file length to attach to.
    ]]
  },

  update_debounce = {
    type = 'number',
    default = 100,
    description = [[
      Debounce time for updates (in milliseconds).
    ]]
  },

  use_internal_diff = {
    type = 'boolean',
    default = [[function()
      if not jit or jit.os == "Windows" then
        return false
      else
        return true
      end
    end]],
    default_help = "true if luajit is present (windows unsupported)",
    description = [[
        Use Neovim's built in xdiff library for running diffs.

        This uses LuaJIT's FFI interface.
    ]]
  },

  use_decoration_api = {
    type = 'boolean',
    default = true,
    description = [[
        Use Neovim's decoration API to apply signs. This should improve
        performance on large files since signs will only be applied to drawn
        lines as opposed to all lines in the buffer.
    ]]
  },

  current_line_blame = {
    type = 'boolean',
    default = false,
    description = [[
        Adds an unobtrusive and customisable blame annotation at the end of
        the current line.

        The highlight group used for the text is `GitSignsCurrentLineBlame`.
    ]]
  },

  current_line_blame_formatter = {
    type = 'function',
    default = [[function(name, blame_info)
      if blame_info.author == name then
        blame_info.author = 'You'
      end

      local text
      if blame_info.author == 'Not Committed Yet' then
        text = blame_info.author
      else
        text = string.format(
          '%s, %s - %s',
          blame_info.author,
          os.date('%Y-%m-%d', tonumber(blame_info['author_time'])),
          blame_info.summary
        )
      end

      return {{' '..text, 'GitSignsCurrentLineBlame'}}
    end]],
    description = [[
        Function used to format the virtual text of
        |gitsigns-config-current_line_blame|. The first argument {name} is the
        git user name returned from: >
            git config user.name
<
        The second argument {blame_info} is a table with the following keys:
        - abbrev_sha: string
        - orig_lnum: integer
        - final_lnum: integer
        - author: string
        - author_mail: string
        - author_time: integer
        - author_tz: string
        - committer: string
        - committer_mail: string
        - committer_time: integer
        - committer_tz: string
        - summary: string
        - previous: string
        - filename: string

        Note that the keys map onto the output of: >
            git blame --line-porcelain
<
    ]]
  },

  _git_version = {
    type = 'string',
    default = 'auto',
    description = [[
        Version of git available. Set to 'auto' to automatically detect.
    ]]
  },

  _refresh_staged_on_update = {
    type = 'boolean',
    default = true,
    description = [[
        Always refresh the staged file on each update. Disabling this will cause
        the staged file to only be refreshed when an update to the index is
        detected.
    ]]
  },

  debug_mode = {
    type = 'boolean',
    default = false,
    description = [[
        Print diagnostic messages.
    ]]
  }
}

local function validate_config(config: {string:any})
  for k, v in pairs(config) do
    if M.schema[k] == nil then
      print(("gitsigns: Ignoring invalid configuration field '%s'"):format(k))
    else
      vim.validate {
        [k] = { v, M.schema[k].type } as {any};
      }
    end
  end
end

local function resolve_default(schema_elem: SchemaElem): any
  local v = schema_elem
  local default = v.default
  if default is string and vim.startswith(default, 'function(') then
    local d = loadstring('return '..default)() as function
    if v.type == 'function' then
      return d
    else
      return d()
    end
  elseif default is string and vim.startswith(default, '{') then
    return loadstring('return '..default)()
  else
    return default
  end
end

function M.process(user_config: {string:any}): M.Config
  user_config = user_config or {}

  validate_config(user_config)

  local config: {string:any} = {}
  for k, v in pairs(M.schema) do
    if user_config[k] ~= nil then
      if v.deep_extend then
        local d = resolve_default(v)
        config[k] = vim.tbl_deep_extend('force', d as table, user_config[k] as table)
      else
        config[k] = user_config[k]
      end
    else
      config[k] = resolve_default(v)
    end
  end

  return config as M.Config
end

return M
