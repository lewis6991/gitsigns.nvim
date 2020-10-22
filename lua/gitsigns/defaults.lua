return {
  signs = {
    add          = {hl = 'GitGutterAdd'   , text = '│'},
    change       = {hl = 'GitGutterChange', text = '│'},
    delete       = {hl = 'GitGutterDelete', text = '_'},
    topdelete    = {hl = 'GitGutterDelete', text = 'X'},
    changedelete = {hl = 'GitGutterChange', text = '~'},
  },
  keymaps = {
    [']c']         = '<cmd>lua require"gitsigns".next_hunk()<CR>',
    ['[c']         = '<cmd>lua require"gitsigns".prev_hunk()<CR>',
    ['<leader>hs'] = '<cmd>lua require"gitsigns".stage_hunk()<CR>',
    ['<leader>gh'] = '<cmd>lua require"gitsigns".get_hunk()<CR>'
  },
  watch_index = {
    enabled = true,
    interval = 1000
  },
  debug_mode = false
}
