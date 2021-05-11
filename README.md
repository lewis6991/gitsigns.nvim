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
- Preview diffs of hunks
- Customisable (signs, highlights, mappings, etc)
- Status bar integration
- Git blame a specific line using virtual text.
- Hunk text object
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
    buffer = true,

    ['n ]c'] = { expr = true, "&diff ? ']c' : '<cmd>lua require\"gitsigns\".next_hunk()<CR>'"},
    ['n [c'] = { expr = true, "&diff ? '[c' : '<cmd>lua require\"gitsigns\".prev_hunk()<CR>'"},

    ['n <leader>hs'] = '<cmd>lua require"gitsigns".stage_hunk()<CR>',
    ['n <leader>hu'] = '<cmd>lua require"gitsigns".undo_stage_hunk()<CR>',
    ['n <leader>hr'] = '<cmd>lua require"gitsigns".reset_hunk()<CR>',
    ['n <leader>hR'] = '<cmd>lua require"gitsigns".reset_buffer()<CR>',
    ['n <leader>hp'] = '<cmd>lua require"gitsigns".preview_hunk()<CR>',
    ['n <leader>hb'] = '<cmd>lua require"gitsigns".blame_line(true)<CR>',

    -- Text objects
    ['o ih'] = ':<C-U>lua require"gitsigns".select_hunk()<CR>',
    ['x ih'] = ':<C-U>lua require"gitsigns".select_hunk()<CR>'
  },
  watch_index = {
    interval = 1000
  },
  current_line_blame = false,
  sign_priority = 6,
  update_debounce = 100,
  status_formatter = nil, -- Use default
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

## Secondary Signs, Staged Hunks and Base Revisions

Gitsigns supports showing signs for two diffs of the same buffer. These signs are configured with `config.signs` and `config.signs_sec` respectively.

One application for a secondary set of signs is for showing staged hunks (hunks in the index but not in `HEAD`). If the default base revision values are used (`config.signs.base=nil` and `config.signs_sec.base=nil`) and `config.staged_signs=true`, Gitsigns will use the secondary set of signs to show staged hunks. If the base revisions are set to any other value then both sets of signs will be shown alongside each other.

For convenience the base revisions can be changed with the action `change_base`:

```viml
:lua require('gitsigns').change_base('HEAD~10')  " Change revision for main signs
:GitSigns change_base HEAD~10                    " or use the CLI
:lua require('gitsigns').change_sec_base('~5')   " Change revision for secondary signs
:GitSigns change_sec_base ~5
```

## TODO

- [x] Add ability to show staged hunks with different signs (maybe in a different sign column?)
- [ ] Add ability to show commit in floating window of current line
- [ ] Allow extra options to be passed to `git diff`
- [ ] Folding of text around hunks
- [x] Diff against working tree instead of index, or diff against any SHA.
- [ ] Open diff mode of buffer against what gitsigns is comparing to (currently the index)
- [ ] Show messages when navigating hunks similar to '/' search

## Similar plugins

- [coc-git](https://github.com/neoclide/coc-git)
- [vim-gitgutter](https://github.com/airblade/vim-gitgutter)
- [vim-signify](https://github.com/mhinz/vim-signify)
