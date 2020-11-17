return {
  signs = {
    add          = {hl = 'DiffAdd'   , text = '│'},
    change       = {hl = 'DiffChange', text = '│'},
    delete       = {hl = 'DiffDelete', text = '_'},
    topdelete    = {hl = 'DiffDelete', text = '‾'},
    changedelete = {hl = 'DiffChange', text = '~'},
  },
  count_chars = {
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
  keymaps = {
    -- Default keymap options
    noremap = true,
    buffer = true,

    ['n ]c'] = { expr = true, "&diff ? ']c' : '<cmd>lua require\"gitsigns\".next_hunk()<CR>'"},
    ['n [c'] = { expr = true, "&diff ? '[c' : '<cmd>lua require\"gitsigns\".prev_hunk()<CR>'"},

    ['n <leader>hs'] = '<cmd>lua require"gitsigns".stage_hunk()<CR>',
    ['n <leader>hu'] = '<cmd>lua require"gitsigns".undo_stage_hunk()<CR>',
    ['n <leader>hr'] = '<cmd>lua require"gitsigns".reset_hunk()<CR>',
    ['n <leader>hp'] = '<cmd>lua require"gitsigns".preview_hunk()<CR>',
  },
  watch_index = {
    interval = 1000
  },
  debug_mode = false,
  sign_priority = 6,
  status_formatter = nil, -- Use default
}
