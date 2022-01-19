local warn
do

   local ok, ret = pcall(require, 'gitsigns.message')
   if ok then
      warn = ret.warn
   end
end

local SchemaElem = {Deprecated = {}, }
















local M = {Config = {DiffOpts = {}, SignsConfig = {}, watch_gitdir = {}, current_line_blame_formatter_opts = {}, current_line_blame_opts = {}, yadm = {}, }, }


















































































M.config = {}

M.schema = {
   signs = {
      type = 'table',
      deep_extend = true,
      default = {
         add = { hl = 'GitSignsAdd', text = '│', numhl = 'GitSignsAddNr', linehl = 'GitSignsAddLn' },
         change = { hl = 'GitSignsChange', text = '│', numhl = 'GitSignsChangeNr', linehl = 'GitSignsChangeLn' },
         delete = { hl = 'GitSignsDelete', text = '_', numhl = 'GitSignsDeleteNr', linehl = 'GitSignsDeleteLn' },
         topdelete = { hl = 'GitSignsDelete', text = '‾', numhl = 'GitSignsDeleteNr', linehl = 'GitSignsDeleteLn' },
         changedelete = { hl = 'GitSignsChange', text = '~', numhl = 'GitSignsChangeNr', linehl = 'GitSignsChangeLn' },
      },
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
        • `Diff*Gutter`
        • `diff*`
        • `Diff*`

      For example if `signs.add.hl = GitSignsAdd` and `GitSignsAdd` is not
      defined but `GitGutterAdd` is defined, then `GitSignsAdd` will be linked
      to `GitGutterAdd`.
    ]],
   },

   keymaps = {
      deprecated = {
         message = "config.keymaps is now deprecated. Please define mappings in config.on_attach() instead.",
      },
      type = 'table',
      default = {},
      description = [[
      Keymaps to set up when attaching to a buffer.

      Each key in the table defines the mode and key (whitespace delimited)
      for the mapping and the value defines what the key maps to. The value
      can be a table which can contain keys matching the options defined in
      |map-arguments| which are: `expr`, `noremap`, `nowait`, `script`, `silent`
      and `unique`.  These options can also be used in the top level of the
      table to define default options for all mappings.

      Since this field is not extended (unlike |gitsigns-config-signs|),
      mappings defined in this field can be disabled by setting the whole field
      to `{}`, and |gitsigns-config-on_attach| can instead be used to define
      mappings.
    ]],
   },

   on_attach = {
      type = 'function',
      default = nil,
      description = [[
      Callback called when attaching to a buffer. Mainly used to setup keymaps
      when `config.keymaps` is empty. The buffer number is passed as the first
      argument.

      This callback can return `false` to prevent attaching to the buffer.

      Example: >
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
      default = {
         interval = 1000,
         follow_files = true,
      },
      description = [[
      When opening a file, a libuv watcher is placed on the respective
      `.git` directory to detect when changes happen to use as a trigger to
      update signs.

      Fields: ~
        • `interval`:
            Interval the watcher waits between polls of the gitdir in milliseconds.

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

      Note: Virtual lines currently use the highlight `GitSignsDeleteLn`.
    ]],
   },

   diff_opts = {
      type = 'table',
      deep_extend = true,
      default = function()
         local r = {
            algorithm = 'myers',
            internal = false,
            indent_heuristic = false,
         }
         for _, o in ipairs(vim.opt.diffopt:get()) do
            if o == 'indent-heuristic' then
               r.indent_heuristic = true
            elseif o == 'internal' then
               if vim.diff then
                  r.internal = true
               elseif jit and jit.os ~= "Windows" then

                  r.internal = true
               end
            elseif vim.startswith(o, 'algorithm:') then
               r.algorithm = string.sub(o, 11)
            end
         end
         return r
      end,
      default_help = "derived from 'diffopt'",
      description = [[
      Diff options.

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

            Note Neovim v0.5 uses LuaJIT's FFI interface, whereas v0.5+ uses
            `vim.diff`.
        • indent_heuristic: string
            Use the indent heuristic for the internal
            diff library.
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
         [1] = '1',
         [2] = '2',
         [3] = '3',
         [4] = '4',
         [5] = '5',
         [6] = '6',
         [7] = '7',
         [8] = '8',
         [9] = '9',
         ['+'] = '>',
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
      default = function(status)
         local added, changed, removed = status.added, status.changed, status.removed
         local status_txt = {}
         if added and added > 0 then table.insert(status_txt, '+' .. added) end
         if changed and changed > 0 then table.insert(status_txt, '~' .. changed) end
         if removed and removed > 0 then table.insert(status_txt, '-' .. removed) end
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
      Max file length to attach to.
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
    ]],
   },

   current_line_blame_formatter_opts = {
      type = 'table',
      deep_extend = true,
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
      type = 'function',
      default = function(name, blame_info, opts)
         if blame_info.author == name then
            blame_info.author = 'You'
         end

         local text
         if blame_info.author == 'Not Committed Yet' then
            text = blame_info.author
         else
            local date_time

            if opts.relative_time then
               date_time = require('gitsigns.util').get_relative_time(tonumber(blame_info['author_time']))
            else
               date_time = os.date('%Y-%m-%d', tonumber(blame_info['author_time']))
            end

            text = string.format('%s, %s - %s', blame_info.author, date_time, blame_info.summary)
         end

         return { { ' ' .. text, 'GitSignsCurrentLineBlame' } }
      end,
      default_help = [[function(name, blame_info, opts)
      if blame_info.author == name then
        blame_info.author = 'You'
      end

      local text
      if blame_info.author == 'Not Committed Yet' then
        text = blame_info.author
      else
        local date_time

        if opts.relative_time then
          date_time = require('gitsigns.util').get_relative_time(tonumber(blame_info['author_time']))
        else
          date_time = os.date('%Y-%m-%d', tonumber(blame_info['author_time']))
        end

        text = string.format('%s, %s - %s', blame_info.author, date_time, blame_info.summary)
      end

      return {{' '..text, 'GitSignsCurrentLineBlame'}}
    end]],
      description = [[
      Function used to format the virtual text of
      |gitsigns-config-current_line_blame|.

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

                     Note that the keys map onto the output of:
                       `git blame --line-porcelain`

        {opts}       Passed directly from
                     |gitsigns-config-current_line_blame_formatter_opts|.

      Return: ~
        The result of this function is passed directly to the `opts.virt_text`
        field of |nvim_buf_set_extmark|.
    ]],
   },

   trouble = {
      type = 'boolean',
      default = function()
         local has_trouble = pcall(require, 'trouble')
         return has_trouble
      end,
      default_help = "true if installed",
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

   word_diff = {
      type = 'boolean',
      default = false,
      description = [[
      Highlight intra-line word differences in the buffer.
      Requires `config.diff_opts.internal = true` .

      Uses the highlights:
        • GitSignsAddLn
        • GitSignsChangeLn
        • GitSignsDeleteLn
    ]],
   },

   _refresh_staged_on_update = {
      type = 'boolean',
      default = true,
      description = [[
      Always refresh the staged file on each update. Disabling this will cause
      the staged file to only be refreshed when an update to the index is
      detected.
    ]],
   },

   _blame_cache = {
      type = 'boolean',
      default = true,
      description = [[
      Cache blame results for current_line_blame
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

   watch_index = { deprecated = { new_field = 'watch_gitdir' } },
   current_line_blame_delay = { deprecated = { new_field = 'current_line_blame_opts.delay' } },
   current_line_blame_position = { deprecated = { new_field = 'current_line_blame_opts.virt_text_pos' } },
   diff_algorithm = { deprecated = { new_field = 'diff_opts.algorithm' } },
   use_decoration_api = { deprecated = true },
   use_internal_diff = { deprecated = { new_field = 'diff_opts.internal' } },
}

warn = function(s, ...)
   vim.notify(s:format(...), vim.log.levels.WARN, { title = 'gitsigns' })
end

local function validate_config(config)
   for k, v in pairs(config) do
      local kschema = M.schema[k]
      if kschema == nil then
         warn("gitsigns: Ignoring invalid configuration field '%s'", k)
      elseif kschema.type then
         vim.validate({
            [k] = { v, kschema.type },
         })
      end
   end
end

local function resolve_default(v)
   if type(v.default) == 'function' and v.type ~= 'function' then
      return (v.default)()
   else
      return v.default
   end
end

local function handle_deprecated(cfg)
   for k, v in pairs(M.schema) do
      local dep = v.deprecated
      if dep and cfg[k] ~= nil then
         if type(dep) == "table" then
            if dep.new_field then
               local opts_key, field = dep.new_field:match('(.*)%.(.*)')
               if opts_key and field then

                  local opts = (cfg[opts_key] or {})
                  opts[field] = cfg[k]
                  cfg[opts_key] = opts
               else

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

function M.build(user_config)
   user_config = user_config or {}

   handle_deprecated(user_config)

   validate_config(user_config)

   local config = M.config
   for k, v in pairs(M.schema) do
      if user_config[k] ~= nil then
         if v.deep_extend then
            local d = resolve_default(v)
            config[k] = vim.tbl_deep_extend('force', d, user_config[k])
         else
            config[k] = user_config[k]
         end
      else
         config[k] = resolve_default(v)
      end
   end
end

return M
