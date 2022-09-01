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
- Asynchronous using [luv]
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
- Support for [yadm]
- Support for detached working trees.

## Requirements

- Neovim >= 0.5.0

  Note: If you are running a development version of Neovim (aka `master`), then breakage may occur if your build is behind latest.
- Newish version of git. Older versions may not work with some features.

## Installation

[packer.nvim]:
```lua
use {
  'lewis6991/gitsigns.nvim',
  -- tag = 'release' -- To use the latest release (do not use this if you run Neovim nightly or dev builds!)
}
```

[vim-plug]:
```vim
Plug 'lewis6991/gitsigns.nvim'
```

## Usage

For basic setup with all batteries included:
```lua
require('gitsigns').setup()
```

If using [packer.nvim] gitsigns can
be setup directly in the plugin spec:

```lua
use {
  'lewis6991/gitsigns.nvim',
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
  current_line_blame_formatter = '<author>, <author_time:%Y-%m-%d> - <summary>',
  sign_priority = 6,
  update_debounce = 100,
  status_formatter = nil, -- Use default
  max_file_length = 40000, -- Disable if file is longer than this (in lines)
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

For information on configuring Neovim via lua please see [nvim-lua-guide].

### Keymaps

Gitsigns provides an `on_attach` callback which can be used to setup buffer mappings.

Here is a suggested example:

```lua
require('gitsigns').setup{
  ...
  on_attach = function(bufnr)
    local gs = package.loaded.gitsigns

    local function map(mode, l, r, opts)
      opts = opts or {}
      opts.buffer = bufnr
      vim.keymap.set(mode, l, r, opts)
    end

    -- Navigation
    map('n', ']c', function()
      if vim.wo.diff then return ']c' end
      vim.schedule(function() gs.next_hunk() end)
      return '<Ignore>'
    end, {expr=true})

    map('n', '[c', function()
      if vim.wo.diff then return '[c' end
      vim.schedule(function() gs.prev_hunk() end)
      return '<Ignore>'
    end, {expr=true})

    -- Actions
    map({'n', 'v'}, '<leader>hs', ':Gitsigns stage_hunk<CR>')
    map({'n', 'v'}, '<leader>hr', ':Gitsigns reset_hunk<CR>')
    map('n', '<leader>hS', gs.stage_buffer)
    map('n', '<leader>hu', gs.undo_stage_hunk)
    map('n', '<leader>hR', gs.reset_buffer)
    map('n', '<leader>hp', gs.preview_hunk)
    map('n', '<leader>hb', function() gs.blame_line{full=true} end)
    map('n', '<leader>tb', gs.toggle_current_line_blame)
    map('n', '<leader>hd', gs.diffthis)
    map('n', '<leader>hD', function() gs.diffthis('~') end)
    map('n', '<leader>td', gs.toggle_deleted)

    -- Text object
    map({'o', 'x'}, 'ih', ':<C-U>Gitsigns select_hunk<CR>')
  end
}
```

Note this requires Neovim v0.7 which introduces `vim.keymap.set`. If you are using Neovim with version prior to v0.7 then use the following:
<details>
  <summary>Click to expand</summary>

```lua
require('gitsigns').setup {
  ...
  on_attach = function(bufnr)
    local function map(mode, lhs, rhs, opts)
        opts = vim.tbl_extend('force', {noremap = true, silent = true}, opts or {})
        vim.api.nvim_buf_set_keymap(bufnr, mode, lhs, rhs, opts)
    end

    -- Navigation
    map('n', ']c', "&diff ? ']c' : '<cmd>Gitsigns next_hunk<CR>'", {expr=true})
    map('n', '[c', "&diff ? '[c' : '<cmd>Gitsigns prev_hunk<CR>'", {expr=true})

    -- Actions
    map('n', '<leader>hs', ':Gitsigns stage_hunk<CR>')
    map('v', '<leader>hs', ':Gitsigns stage_hunk<CR>')
    map('n', '<leader>hr', ':Gitsigns reset_hunk<CR>')
    map('v', '<leader>hr', ':Gitsigns reset_hunk<CR>')
    map('n', '<leader>hS', '<cmd>Gitsigns stage_buffer<CR>')
    map('n', '<leader>hu', '<cmd>Gitsigns undo_stage_hunk<CR>')
    map('n', '<leader>hR', '<cmd>Gitsigns reset_buffer<CR>')
    map('n', '<leader>hp', '<cmd>Gitsigns preview_hunk<CR>')
    map('n', '<leader>hb', '<cmd>lua require"gitsigns".blame_line{full=true}<CR>')
    map('n', '<leader>tb', '<cmd>Gitsigns toggle_current_line_blame<CR>')
    map('n', '<leader>hd', '<cmd>Gitsigns diffthis<CR>')
    map('n', '<leader>hD', '<cmd>lua require"gitsigns".diffthis("~")<CR>')
    map('n', '<leader>td', '<cmd>Gitsigns toggle_deleted<CR>')

    -- Text object
    map('o', 'ih', ':<C-U>Gitsigns select_hunk<CR>')
    map('x', 'ih', ':<C-U>Gitsigns select_hunk<CR>')
  end
}
```

</details>

## Non-Goals

### Implement every feature in [vim-fugitive]

This plugin is actively developed and by one of the most well regarded vim plugin developers.
Gitsigns will only implement features of this plugin if: it is simple, or, the technologies leveraged by Gitsigns (LuaJIT, Libuv, Neovim's API, etc) can provide a better experience.

### Support for other VCS

There aren't any active developers of this plugin who use other kinds of VCS, so adding support for them isn't feasible.
However a well written PR with a commitment of future support could change this.

## Status Line

Use `b:gitsigns_status` or `b:gitsigns_status_dict`. `b:gitsigns_status` is
formatted using `config.status_formatter`. `b:gitsigns_status_dict` is a
dictionary with the keys `added`, `removed`, `changed` and `head`.

Example:
```viml
set statusline+=%{get(b:,'gitsigns_status','')}
```

For the current branch use the variable `b:gitsigns_head`.

## Comparison with [vim-gitgutter]

Feature                                                  | gitsigns.nvim        | vim-gitgutter                                 | Note
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

As of 2022-09-01

## Integrations

### [vim-repeat]

If installed, `stage_hunk()` and `reset_hunk()` are repeatable with the `.` (dot) operator.

### [vim-fugitive]

When viewing revisions of a file (via `:0Gclog` for example), Gitsigns will attach to the fugitive buffer with the base set to the commit immediately before the commit of that revision.
This means the signs placed in the buffer reflect the changes introduced by that revision of the file.

### [null-ls]

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

### [trouble.nvim]

If installed and enabled (via `config.trouble`; defaults to true if installed), `:Gitsigns setqflist` or `:Gitsigns seqloclist` will open Trouble instead of Neovim's built-in quickfix or location list windows.

## Similar plugins

- [coc-git]
- [vim-gitgutter]
- [vim-signify]

<!-- links -->
[coc-git]: https://github.com/neoclide/coc-git
[luv]: https://github.com/luvit/luv/blob/master/docs.md
[null-ls]: https://github.com/jose-elias-alvarez/null-ls.nvim
[nvim-lua-guide]: https://github.com/nanotee/nvim-lua-guide
[packer.nvim]: https://github.com/wbthomason/packer.nvim
[trouble.nvim]: https://github.com/folke/trouble.nvim
[vim-fugitive]: https://github.com/tpope/vim-fugitive
[vim-gitgutter]: https://github.com/airblade/vim-gitgutter
[vim-plug]: https://github.com/junegunn/vim-plug
[vim-repeat]: https://github.com/tpope/vim-repeat
[vim-signify]: https://github.com/mhinz/vim-signify
[yadm]: https://yadm.io
