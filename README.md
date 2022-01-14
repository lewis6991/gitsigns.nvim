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
- Ability to display deleted/changed lines via virtual lines.
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
  },
  -- tag = 'release' -- To use the latest release
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
  signcolumn = true,  -- Toggle with `:Gitsigns toggle_signs`
  numhl      = false, -- Toggle with `:Gitsigns toggle_numhl`
  linehl     = false, -- Toggle with `:Gitsigns toggle_linehl`
  word_diff  = false, -- Toggle with `:Gitsigns toggle_word_diff`
  keymaps = {
    -- Default keymap options
    noremap = true,

    ['n ]c'] = { expr = true, "&diff ? ']c' : '<cmd>Gitsigns next_hunk<CR>'"},
    ['n [c'] = { expr = true, "&diff ? '[c' : '<cmd>Gitsigns prev_hunk<CR>'"},

    ['n <leader>hs'] = '<cmd>Gitsigns stage_hunk<CR>',
    ['v <leader>hs'] = ':Gitsigns stage_hunk<CR>',
    ['n <leader>hu'] = '<cmd>Gitsigns undo_stage_hunk<CR>',
    ['n <leader>hr'] = '<cmd>Gitsigns reset_hunk<CR>',
    ['v <leader>hr'] = ':Gitsigns reset_hunk<CR>',
    ['n <leader>hR'] = '<cmd>Gitsigns reset_buffer<CR>',
    ['n <leader>hp'] = '<cmd>Gitsigns preview_hunk<CR>',
    ['n <leader>hb'] = '<cmd>lua require"gitsigns".blame_line{full=true}<CR>',
    ['n <leader>hS'] = '<cmd>Gitsigns stage_buffer<CR>',
    ['n <leader>hU'] = '<cmd>Gitsigns reset_buffer_index<CR>',

    -- Text objects
    ['o ih'] = ':<C-U>Gitsigns select_hunk<CR>',
    ['x ih'] = ':<C-U>Gitsigns select_hunk<CR>'
  },
  watch_gitdir = {
    interval = 1000,
    follow_files = true
  },
  attach_to_untracked = true,
  current_line_blame = false, -- Toggle with `:Gitsigns toggle_current_line_blame`
  current_line_blame_opts = {
    virt_text = true,
    virt_text_pos = 'eol', -- 'eol' | 'overlay' | 'right_align'
    delay = 1000,
    ignore_whitespace = false,
  },
  current_line_blame_formatter_opts = {
    relative_time = false
  },
  sign_priority = 6,
  update_debounce = 100,
  status_formatter = nil, -- Use default
  max_file_length = 40000,
  preview_config = {
    -- Options passed to nvim_open_win
    border = 'single',
    style = 'minimal',
    relative = 'cursor',
    row = 0,
    col = 1
  },
  yadm = {
    enable = false
  },
}
```

For information on configuring neovim via lua please see
[nvim-lua-guide](https://github.com/nanotee/nvim-lua-guide).

## Non-Goals

### Implement every feature in [vim-fugitive](https://github.com/tpope/vim-fugitive)

This plugin is actively developed and by one of the most well regarded vim plugin developers. Gitsigns will only implement features of this plugin if: it is simple, or, the technologies leveraged by Gitsigns (LuaJIT, Libuv, Neovim's API, etc) can provide a better experience.

### Support for other VCS

There aren't any active developers of this plugin who use other kinds of VCS, so adding support for them isn't feasible. However a well written PR with a commitment of future support could change this.

## Status Line

Use `b:gitsigns_status` or `b:gitsigns_status_dict`. `b:gitsigns_status` is
formatted using `config.status_formatter`. `b:gitsigns_status_dict` is a
dictionary with the keys `added`, `removed`, `changed` and `head`.

Example:
```viml
set statusline+=%{get(b:,'gitsigns_status','')}
```

For the current branch use the variable `b:gitsigns_head`.

## Comparison with [vim-gitgutter](https://github.com/airblade/vim-gitgutter)

Feature                                                  | gitsigns             | gitgutter                                     | Note
---------------------------------------------------------|----------------------|-----------------------------------------------|--------
Shows signs for added, modified, and removed lines       | :white_check_mark:   | :white_check_mark:                            |
Asynchronous                                             | :white_check_mark:   | :white_check_mark:                            |
Runs diffs in-process (no IO or pipes)                   | :white_check_mark: * |                                               | * Via [lua](https://github.com/neovim/neovim/pull/14536) or FFI.
Only adds signs for drawn lines                          | :white_check_mark: * |                                               | * Via Neovims decoration API
Updates immediately                                      | :white_check_mark:   | *                                             | * Triggered on CursorHold
Ensures signs are always up to date                      | :white_check_mark: * |                                               | * Watches the git dir to do so
Never saves the buffer                                   | :white_check_mark:   | :white_check_mark: :heavy_exclamation_mark: * | * Writes [buffer](https://github.com/airblade/vim-gitgutter/blob/0f98634b92da9a35580b618c11a6d2adc42d9f90/autoload/gitgutter/diff.vim#L106) (and index) to short lived temp files
Quick jumping between hunks                              | :white_check_mark:   | :white_check_mark:                            |
Stage/reset/preview individual hunks                     | :white_check_mark:   | :white_check_mark:                            |
Stage/reset hunks in range/selection                     | :white_check_mark:   | :white_check_mark: :heavy_exclamation_mark: * | * Only stage
Stage/reset all hunks in buffer                          | :white_check_mark:   |                                               |
Undo staged hunks                                        | :white_check_mark:   |                                               |
Word diff in buffer                                      | :white_check_mark:   |                                               |
Word diff in hunk preview                                | :white_check_mark:   | :white_check_mark:                            |
Show deleted/changes lines directly in buffer            | :white_check_mark: * |                                               | * Via [virtual lines](https://github.com/neovim/neovim/pull/15351)
Stage partial hunks                                      | :white_check_mark:   |                                               |
Hunk text object                                         | :white_check_mark:   | :white_check_mark:                            |
Diff against index or any commit                         | :white_check_mark:   | :white_check_mark:                            |
Folding of unchanged text                                |                      | :white_check_mark:                            |
Fold text showing whether folded lines have been changed |                      | :white_check_mark:                            |
Load hunk locations into the quickfix or location list   | :white_check_mark:   | :white_check_mark:                            |
Optional line highlighting                               | :white_check_mark:   | :white_check_mark:                            |
Optional line number highlighting                        | :white_check_mark:   | :white_check_mark:                            |
Optional counts on signs                                 | :white_check_mark:   |                                               |
Customizable signs and mappings                          | :white_check_mark:   | :white_check_mark:                            |
Customizable extra diff arguments                        | :white_check_mark:   | :white_check_mark:                            |
Can be toggled globally or per buffer                    | :white_check_mark: * | :white_check_mark:                            | * Through the detach/attach functions
Statusline integration                                   | :white_check_mark:   | :white_check_mark:                            |
Works with [yadm](https://yadm.io/)                      | :white_check_mark:   |                                               |
Live blame in buffer (using virtual text)                | :white_check_mark:   |                                               |
Blame preview                                            | :white_check_mark:   |                                               |
Automatically follows open files moved with `git mv`     | :white_check_mark:   |                                               |
CLI with completion                                      | :white_check_mark:   | *                                             | * Provides individual commands for some actions
Open diffview with any revision/commit                   | :white_check_mark:   |                                               |

As of 2021-07-05

## Integrations

### [vim-repeat](https://github.com/tpope/vim-repeat)

If installed, `stage_hunk()` and `reset_hunk()` are repeatable with the `.` (dot) operator.

### [vim-fugitive](https://github.com/tpope/vim-fugitive)

When viewing revisions of a file (via `:0Gclog` for example), Gitsigns will attach to the fugitive buffer with the base set to the commit immediately before the commit of that revision. This means the signs placed in the buffer reflect the changes introduced by that revision of the file.

### [null-ls](https://github.com/jose-elias-alvarez/null-ls.nvim)

Null-ls can provide code actions from Gitsigns. To setup:

```lua
local null_ls = require("null-ls")

null_ls.setup {
  sources = {
    null_ls.builtins.code_actions.gitsigns,
    ...
  }
}
```

Will enable `:lua vim.lsp.buf.code_action()` to retrieve code actions from Gitsigns.
Alternatively if you have [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) installed, you can use `:Telescope lsp_code_actions`.

### [trouble.nvim](https://github.com/folke/trouble.nvim)

If installed and enabled (via `config.trouble`; defaults to true if installed), `:Gitsigns setqflist` or `:Gitsigns seqloclist` will open Trouble instead of Neovim's built-in quickfix or location list windows.

## Similar plugins

- [coc-git](https://github.com/neoclide/coc-git)
- [vim-gitgutter](https://github.com/airblade/vim-gitgutter)
- [vim-signify](https://github.com/mhinz/vim-signify)
