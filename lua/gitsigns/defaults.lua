return {
  signs = {
    add          = {hl = 'DiffAdd'   , text = '│'},
    change       = {hl = 'DiffChange', text = '│'},
    delete       = {hl = 'DiffDelete', text = '_'},
    topdelete    = {hl = 'DiffDelete', text = 'X'},
    changedelete = {hl = 'DiffChange', text = '~'},
  },
  keymaps = {
    [']c']         = '<cmd>lua require"gitsigns".next_hunk()<CR>',
    ['[c']         = '<cmd>lua require"gitsigns".prev_hunk()<CR>',
    ['<leader>hs'] = '<cmd>lua require"gitsigns".stage_hunk()<CR>',
    ['<leader>hu'] = '<cmd>lua require"gitsigns".undo_stage_hunk()<CR>',
    ['<leader>hr'] = '<cmd>lua require"gitsigns".reset_hunk()<CR>',
  },
  watch_index = {
    interval = 1000
  },
  debug_mode = false
}
