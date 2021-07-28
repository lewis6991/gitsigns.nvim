# gitsigns.nvim

[![CI](https://github.com/lewis6991/gitsigns.nvim/workflows/CI/badge.svg?branch=main)](https://github.com/lewis6991/gitsigns.nvim/actions?query=workflow%3ACI)
[![Version](https://img.shields.io/github/v/release/lewis6991/gitsigns.nvim)](https://github.com/lewis6991/gitsigns.nvim/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Gitter](https://badges.gitter.im/gitsigns-nvim/community.svg)](https://gitter.im/gitsigns-nvim/community?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge)

Super fast git decorations implemented purely in lua/teal.

## Preview

| Hunk Actions | Line Blame |
| --- | ----------- |
| <img src="https://raw.githubusercontent.com/lewis6991/media/main/gitsigns_actions.gif" width="450em"/> | <img src="https://raw.githubusercontent.com/lewis6991/media/main/gitsigns_blame.gif" width="450em"/> |

## Features

- Signs for added, removed, and changed lines
- Asynchronous using [luv](https://github.com/luvit/luv/blob/master/docs.md)
- Navigation between hunks
- Stage hunks (with undo)
- Preview diffs of hunks (with word diff)
- Customisable (signs, highlights, mappings, etc)
- Status bar integration
- Git blame a specific line using virtual text.
- Hunk text object
- Automatically follow files moved in the index.
- Live intra-line word diff
- Support for [yadm](https://yadm.io/)

## Requirements

- Neovim >= 0.5.0
- Newish version of git. Older versions may not work with some features.

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

If using [packer.nvim](https://github.com/wbthomason/packer.nvim) gitsigns can
be setup directly in the plugin spec:

```lua
use {
  'lewis6991/gitsigns.nvim',
  requires = {
    'nvim-lua/plenary.nvim'
  },
  config = function()
    require('gitsigns').setup()
  end
}
```

Configuration can be passed to the setup function. Here is an example with most of
the default settings:

```lua
require('gitsigns').setup {
  signs = {
    add          = {hl = 'GitSignsAdd'   , text = '│', numhl='GitSignsAddNr'   , linehl='GitSignsAddLn'},
    change       = {hl = 'GitSignsChange', text = '│', numhl='GitSignsChangeNr', linehl='GitSignsChangeLn'},
    delete       = {hl = 'GitSignsDelete', text = '_', numhl='GitSignsDeleteNr', linehl='GitSignsDeleteLn'},
    topdelete    = {hl = 'GitSignsDelete', text = '‾', numhl='GitSignsDeleteNr', linehl='GitSignsDeleteLn'},
    changedelete = {hl = 'GitSignsChange', text = '~', numhl='GitSignsChangeNr', linehl='GitSignsChangeLn'},
  },
  numhl = false,
  linehl = false,
  keymaps = {
    -- Default keymap options
    noremap = true,

    ['n ]c'] = { expr = true, "&diff ? ']c' : '<cmd>lua require\"gitsigns.actions\".next_hunk()<CR>'"},
    ['n [c'] = { expr = true, "&diff ? '[c' : '<cmd>lua require\"gitsigns.actions\".prev_hunk()<CR>'"},

    ['n <leader>hs'] = '<cmd>lua require"gitsigns".stage_hunk()<CR>',
    ['v <leader>hs'] = '<cmd>lua require"gitsigns".stage_hunk({vim.fn.line("."), vim.fn.line("v")})<CR>',
    ['n <leader>hu'] = '<cmd>lua require"gitsigns".undo_stage_hunk()<CR>',
    ['n <leader>hr'] = '<cmd>lua require"gitsigns".reset_hunk()<CR>',
    ['v <leader>hr'] = '<cmd>lua require"gitsigns".reset_hunk({vim.fn.line("."), vim.fn.line("v")})<CR>',
    ['n <leader>hR'] = '<cmd>lua require"gitsigns".reset_buffer()<CR>',
    ['n <leader>hp'] = '<cmd>lua require"gitsigns".preview_hunk()<CR>',
    ['n <leader>hb'] = '<cmd>lua require"gitsigns".blame_line(true)<CR>',

    -- Text objects
    ['o ih'] = ':<C-U>lua require"gitsigns.actions".select_hunk()<CR>',
    ['x ih'] = ':<C-U>lua require"gitsigns.actions".select_hunk()<CR>'
  },
  watch_index = {
    interval = 1000,
    follow_files = true
  },
  current_line_blame = false,
  current_line_blame_delay = 1000,
  current_line_blame_position = 'eol',
  sign_priority = 6,
  update_debounce = 100,
  status_formatter = nil, -- Use default
  word_diff = false,
  use_decoration_api = true,
  use_internal_diff = true,  -- If luajit is present
}
```

For information on configuring neovim via lua please see
[nvim-lua-guide](https://github.com/nanotee/nvim-lua-guide).

## Status Line

Use `b:gitsigns_status` or `b:gitsigns_status_dict`. `b:gitsigns_status` is
formatted using `config.status_formatter`. `b:gitsigns_status_dict` is a
dictionary with the keys `added`, `removed`, `changed` and `head`.

Example:
```viml
set statusline+=%{get(b:,'gitsigns_status','')}
```

For the current branch use the variable `b:gitsigns_head`.

## TODO

- [ ] Add ability to show staged hunks with different signs (maybe in a different sign column?)
- [ ] Add ability to show commit in floating window of current line
- [ ] Allow extra options to be passed to `git diff`
- [ ] Folding of text around hunks
- [ ] Show messages when navigating hunks similar to '/' search
- [ ] Stage partial hunks

## Comparison with [vim-gitgutter](https://github.com/airblade/vim-gitgutter)

Feature                                                  | gitsigns             | gitgutter                                     | Note
---------------------------------------------------------|----------------------|-----------------------------------------------|--------
Shows signs for added, modified, and removed lines       | :white_check_mark:   | :white_check_mark:                            |
Asynchronous                                             | :white_check_mark:   | :white_check_mark:                            |
Runs diffs in-process (no IO or pipes)                   | :white_check_mark: * |                                               | * Via FFI and soon via [lua](https://github.com/neovim/neovim/pull/14536)
Only adds signs for drawn lines                          | :white_check_mark: * |                                               | * Via Neovims decoration API
Updates immediately                                      | :white_check_mark:   | *                                             | * Triggered on CursorHold
Ensures signs are always up to date                      | :white_check_mark: * |                                               | * Watches the git index to do so
Never saves the buffer                                   | :white_check_mark:   | :white_check_mark: :heavy_exclamation_mark: * | * Writes [buffer](https://github.com/airblade/vim-gitgutter/blob/0f98634b92da9a35580b618c11a6d2adc42d9f90/autoload/gitgutter/diff.vim#L106) (and index) to short lived temp files
Quick jumping between hunks                              | :white_check_mark:   | :white_check_mark:                            |
Stage/reset/preview individual hunks                     | :white_check_mark:   | :white_check_mark:                            |
Stage/reset hunks in range/selection                     | :white_check_mark:   | :white_check_mark: :heavy_exclamation_mark: * | * Only stage
Stage/reset all hunks in buffer                          | :white_check_mark:   |                                               |
Undo staged hunks                                        | :white_check_mark:   |                                               |
Word diff in buffer                                      | :white_check_mark:   |                                               |
Word diff in hunk preview                                | :white_check_mark:   | :white_check_mark:                            |
Stage partial hunks                                      |                      | :white_check_mark:                            |
Hunk text object                                         | :white_check_mark:   | :white_check_mark:                            |
Diff against index or any commit                         | :white_check_mark:   | :white_check_mark:                            |
Folding of unchanged text                                |                      | :white_check_mark:                            |
Fold text showing whether folded lines have been changed |                      | :white_check_mark:                            |
Load hunk locations into the quickfix or location list   | :white_check_mark:   | :white_check_mark:                            |
Optional line highlighting                               | :white_check_mark:   | :white_check_mark:                            |
Optional line number highlighting                        | :white_check_mark:   | :white_check_mark:                            |
Optional counts on signs                                 | :white_check_mark:   |                                               |
Customizable signs and mappings                          | :white_check_mark:   | :white_check_mark:                            |
Customizable extra git-diff arguments                    |                      | :white_check_mark:                            |
Can be toggled globally or per buffer                    | :white_check_mark: * | :white_check_mark:                            | * Through the detach/attach functions
Statusline integration                                   | :white_check_mark:   | :white_check_mark:                            |
Works with [yadm](https://yadm.io/)                      | :white_check_mark:   |                                               |
Live blame in buffer (using virtual text)                | :white_check_mark:   |                                               |
Blame preview                                            | :white_check_mark:   |                                               |
Automatically follows open files moved with `git mv`     | :white_check_mark:   |                                               |
CLI with completion                                      | :white_check_mark:   | *                                             | * Provides individual commands for some actions
Open diffview with any revision/commit                   | :white_check_mark:   |                                               |

As of 2021-07-05

## Similar plugins

- [coc-git](https://github.com/neoclide/coc-git)
- [vim-gitgutter](https://github.com/airblade/vim-gitgutter)
- [vim-signify](https://github.com/mhinz/vim-signify)
