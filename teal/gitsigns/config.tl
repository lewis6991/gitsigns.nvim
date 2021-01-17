
local record SchemaElem
    type: string
    deep_extend: boolean
    default: any
    default_help: string
    description: string
end

local schema: {string:SchemaElem} = {
  signs = {
    type = 'table',
    deep_extend = true,
    default = [[{
      add          = {hl = 'DiffAdd'   , text = '│', numhl='GitSignsAddNr'},
      change       = {hl = 'DiffChange', text = '│', numhl='GitSignsChangeNr'},
      delete       = {hl = 'DiffDelete', text = '_', numhl='GitSignsDeleteNr'},
      topdelete    = {hl = 'DiffDelete', text = '‾', numhl='GitSignsDeleteNr'},
      changedelete = {hl = 'DiffChange', text = '~', numhl='GitSignsChangeNr'},
    }]],
    description = [[
        Configuration for signs:
          • `hl` specifies the highlight group to use for the sign.
          • `text` specifies the character to use for the sign.
          • `numhl` specifies the highlight group to use for the number column (see
            |gitsigns-config.numhl|).
          • `show_count` to enable showing count of hunk, e.g. number of deleted
            lines.
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
      ['n <leader>hp'] = '<cmd>lua require"gitsigns".preview_hunk()<CR>',
      ['n <leader>hb'] = '<cmd>lua require"gitsigns".blame_line()<CR>',

      ['o ih'] = ':<C-U>lua require"gitsigns".text_object()<CR>',
      ['x ih'] = ':<C-U>lua require"gitsigns".text_object()<CR>'
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
    if schema[k] == nil then
      print(("gitsigns: Ignoring invalid configuration field '%s'"):format(k))
    else
      vim.validate {
        [k] = { v, schema[k].type } as {any};
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

return {
  process = function(user_config: {string:any}): {string: any}
    user_config = user_config or {}

    validate_config(user_config)

    local config: {string:any} = {}
    for k, v in pairs(schema) do
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

    return config
  end,
  schema = schema
}
