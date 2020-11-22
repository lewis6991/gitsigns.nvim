
local schema = {
  signs = {
    type = 'table',
    deep_extend = true,
    default = {
      add          = {hl = 'DiffAdd'   , text = '│', numhl='GitSignsAddNr'},
      change       = {hl = 'DiffChange', text = '│', numhl='GitSignsChangeNr'},
      delete       = {hl = 'DiffDelete', text = '_', numhl='GitSignsDeleteNr'},
      topdelete    = {hl = 'DiffDelete', text = '‾', numhl='GitSignsDeleteNr'},
      changedelete = {hl = 'DiffChange', text = '~', numhl='GitSignsChangeNr'},
    }
  },

  numhl = {
    type = 'boolean',
    default = false
  },

  watch_index = {
    type = 'table',
    default = {
      interval = 1000
    }
  },

  debug_mode = {
    type = 'boolean',
    default = false
  },

  sign_priority = {
    type = 'number',
    default = 6
  },

  diff_algorithm = {
    type = 'string',

    -- Get algorithm from 'diffopt'
    default = function()
      local algo = 'myers'
      for o in vim.gsplit(vim.o.diffopt, ',') do
        if vim.startswith(o, 'algorithm:') then
          algo = string.sub(o, 11)
        end
      end
      return algo
    end
  },

  keymaps = {
    type = 'table',
    default = {
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
    }
  },

  status_formatter = {
    type = 'function',
    default = function(status)
      local added, changed, removed = status.added, status.changed, status.removed
      local status_txt = {}
      if added   > 0 then table.insert(status_txt, '+'..added  ) end
      if changed > 0 then table.insert(status_txt, '~'..changed) end
      if removed > 0 then table.insert(status_txt, '-'..removed) end
      return table.concat(status_txt, ' ')
    end
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
    }
  }
}

local function validate_config(config)
  for k, v in pairs(config) do
    if schema[k] == nil then
      print(("gitsigns: Ignoring invalid configuration field '%s'"):format(k))
    else
      vim.validate {
        [k] = { v, schema[k].type };
      }
    end
  end
end

return function(user_config)
  user_config = user_config or {}

  validate_config(user_config)

  local config = {}
  for k, v in pairs(schema) do
    if user_config[k] ~= nil then
      if v.deep_extend then
        config[k] = vim.tbl_deep_extend('force', v.default, user_config[k])
      else
        config[k] = user_config[k]
      end
    else
      if type(v.default) == 'function' and v.type ~= 'function' then
        config[k] = v.default()
      else
        config[k] = v.default
      end
    end
  end

  return config
end
