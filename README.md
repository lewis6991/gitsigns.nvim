# gitsigns.nvim

[![CI](https://github.com/lewis6991/gitsigns.nvim/workflows/CI/badge.svg?branch=main)](https://github.com/lewis6991/gitsigns.nvim/actions?query=workflow%3ACI)

Git signs written in pure lua.

![](https://raw.githubusercontent.com/lewis6991/media/main/gitsigns_demo1.gif)

## Status
**WIP**

Expect things to sometimes break but please don't hesitate to raise an issue.

## Features

- Signs for added, removed, and changed lines
- Asynchronous using [luv](https://github.com/luvit/luv/blob/master/docs.md)
- Navigation between diff blocks (hunks)
- Stage partial diffs (with undo)
- Customisable (signs, highlights, mappings, etc)
- Status bar integration
- Git blame a specific line

## Requirements
Neovim nightly

## Installation

[packer.nvim](https://github.com/wbthomason/packer.nvim):
```lua
use {
  'lewis6991/gitsigns.nvim',
  requires = {
    'nvim-lua/plenary.nvim'
  }
}
```

[vim-plug](https://github.com/junegunn/vim-plug):
```vim
Plug 'nvim-lua/plenary.nvim'
Plug 'lewis6991/gitsigns.nvim'
```

## Usage

For basic setup with all batteries included:
```lua
require('gitsigns').setup()
```

Configuration can be passed to the setup function. Here is an example with all
the default settings:

```lua
require('gitsigns').setup {
  signs = {
    add          = {hl = 'DiffAdd'   , text = '│'},
    change       = {hl = 'DiffChange', text = '│'},
    delete       = {hl = 'DiffDelete', text = '_'},
    topdelete    = {hl = 'DiffDelete', text = '‾'},
    changedelete = {hl = 'DiffChange', text = '~'},
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
    ['n <leader>hb'] = '<cmd>lua require"gitsigns".blame_line()<CR>',
  },
  watch_index = {
    interval = 1000
  },
  sign_priority = 6,
  status_formatter = nil, -- Use default
}
```

For information on configuring neovim via lua please see
[nvim-lua-guide](https://github.com/nanotee/nvim-lua-guide).

## Status Line

Use `b:gitsigns_status` or `b:gitsigns_status_dict`. `b:gitsigns_status` is a
is formatted using `config.status_formatter`. `b:gitsigns_status_dict`is a
dictionary with the keys `added`, `removed`, `changed` and `head`.

Example:
```viml
set statusline+=%{get(b:,'gitsigns_status','')}
```

For the current branch use the variable `b:gitsigns_head`.

## TODO

- [x] Add action for undoing a stage of a hunk
- [x] Add action for ~~undoing~~ reseting a hunk
- [x] Add action for showing diff (or original text) in a floating window
- [ ] Add ability to show staged hunks with different signs (maybe in a different sign column?)
- [x] Add support for repeat.vim
- [ ] Apply buffer updates incrementally
- [x] Add tests
- [x] Respect algorithm in diffopt
- [x] When detecting index changes, also check if the file of the buffer changed
- [ ] Add ability to show commit in floating window of current line
- [x] Add help doc

