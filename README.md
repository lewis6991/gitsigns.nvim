# gitsigns.nvim

[![CI](https://github.com/lewis6991/gitsigns.nvim/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/lewis6991/gitsigns.nvim/actions?query=workflow%3ACI)
[![Version](https://img.shields.io/github/v/release/lewis6991/gitsigns.nvim)](https://github.com/lewis6991/gitsigns.nvim/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Gitter](https://badges.gitter.im/gitsigns-nvim/community.svg)](https://gitter.im/gitsigns-nvim/community?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge)
<a href="https://dotfyle.com/plugins/lewis6991/gitsigns.nvim">
  <img src="https://dotfyle.com/plugins/lewis6991/gitsigns.nvim/shield" />
</a>


Super fast git decorations implemented purely in Lua.

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
- Customizable (signs, highlights, mappings, etc)
- Status bar integration
- Git blame a whole buffer or a specific line.
- Hunk text object
- Automatically follow files moved in the index.
- Live intra-line word diff
- Ability to display deleted/changed lines via virtual lines.
- Support for detached working trees.

## Requirements

- Neovim >= 0.9.0

  **Note:** If your version of Neovim is too old, then you can use a past [release].

  **Note:** If you are running a development version of Neovim (aka `master`), then breakage may occur if your build is behind latest.

- Newish version of git. Older versions may not work with some features.

## Installation & Usage

Install using your package manager of choice.

For recommended setup with all batteries included:
```lua
require('gitsigns').setup()
```

Configuration can be passed to the setup function. Here is an example with most of
the default settings:

```lua
require('gitsigns').setup {
  signs = {
    add          = { text = '┃' },
    change       = { text = '┃' },
    delete       = { text = '_' },
    topdelete    = { text = '‾' },
    changedelete = { text = '~' },
    untracked    = { text = '┆' },
  },
  signs_staged = {
    add          = { text = '┃' },
    change       = { text = '┃' },
    delete       = { text = '_' },
    topdelete    = { text = '‾' },
    changedelete = { text = '~' },
    untracked    = { text = '┆' },
  },
  signs_staged_enable = true,
  signcolumn = true,  -- Toggle with `:Gitsigns toggle_signs`
  numhl      = false, -- Toggle with `:Gitsigns toggle_numhl`
  linehl     = false, -- Toggle with `:Gitsigns toggle_linehl`
  word_diff  = false, -- Toggle with `:Gitsigns toggle_word_diff`
  watch_gitdir = {
    follow_files = true
  },
  auto_attach = true,
  attach_to_untracked = false,
  current_line_blame = false, -- Toggle with `:Gitsigns toggle_current_line_blame`
  current_line_blame_opts = {
    virt_text = true,
    virt_text_pos = 'eol', -- 'eol' | 'overlay' | 'right_align'
    delay = 1000,
    ignore_whitespace = false,
    virt_text_priority = 100,
    use_focus = true,
  },
  current_line_blame_formatter = '<author>, <author_time:%R> - <summary>',
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
    local gitsigns = require('gitsigns')

    local function map(mode, l, r, opts)
      opts = opts or {}
      opts.buffer = bufnr
      vim.keymap.set(mode, l, r, opts)
    end

    -- Navigation
    map('n', ']c', function()
      if vim.wo.diff then
        vim.cmd.normal({']c', bang = true})
      else
        gitsigns.nav_hunk('next')
      end
    end)

    map('n', '[c', function()
      if vim.wo.diff then
        vim.cmd.normal({'[c', bang = true})
      else
        gitsigns.nav_hunk('prev')
      end
    end)

    -- Actions
    map('n', '<leader>hs', gitsigns.stage_hunk)
    map('n', '<leader>hr', gitsigns.reset_hunk)

    map('v', '<leader>hs', function()
      gitsigns.stage_hunk({ vim.fn.line('.'), vim.fn.line('v') })
    end)

    map('v', '<leader>hr', function()
      gitsigns.reset_hunk({ vim.fn.line('.'), vim.fn.line('v') })
    end)

    map('n', '<leader>hS', gitsigns.stage_buffer)
    map('n', '<leader>hR', gitsigns.reset_buffer)
    map('n', '<leader>hp', gitsigns.preview_hunk)
    map('n', '<leader>hi', gitsigns.preview_hunk_inline)

    map('n', '<leader>hb', function()
      gitsigns.blame_line({ full = true })
    end)

    map('n', '<leader>hd', gitsigns.diffthis)

    map('n', '<leader>hD', function()
      gitsigns.diffthis('~')
    end)

    map('n', '<leader>hQ', function() gitsigns.setqflist('all') end)
    map('n', '<leader>hq', gitsigns.setqflist)

    -- Toggles
    map('n', '<leader>tb', gitsigns.toggle_current_line_blame)
    map('n', '<leader>td', gitsigns.toggle_deleted)
    map('n', '<leader>tw', gitsigns.toggle_word_diff)

    -- Text object
    map({'o', 'x'}, 'ih', ':<C-U>Gitsigns select_hunk<CR>')
  end
}
```

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

### [vim-fugitive]

When viewing revisions of a file (via `:0Gclog` for example), Gitsigns will attach to the fugitive buffer with the base set to the commit immediately before the commit of that revision.
This means the signs placed in the buffer reflect the changes introduced by that revision of the file.

### [trouble.nvim]

If installed and enabled (via `config.trouble`; defaults to true if installed), `:Gitsigns setqflist` or `:Gitsigns setloclist` will open Trouble instead of Neovim's built-in quickfix or location list windows.

### [lspsaga.nvim]

If you are using lspsaga.nvim you can config `code_action.extend_gitsigns` (default is false) to show the gitsigns action in lspsaga codeaction.

## Similar plugins

- [mini.diff]
- [coc-git]
- [vim-gitgutter]
- [vim-signify]

<!-- links -->
[mini.diff]: https://github.com/echasnovski/mini.diff
[coc-git]: https://github.com/neoclide/coc-git
[diff-linematch]: https://github.com/neovim/neovim/pull/14537
[luv]: https://github.com/luvit/luv/blob/master/docs.md
[nvim-lua-guide]: https://neovim.io/doc/user/lua-guide.html
[release]: https://github.com/lewis6991/gitsigns.nvim/releases
[trouble.nvim]: https://github.com/folke/trouble.nvim
[vim-fugitive]: https://github.com/tpope/vim-fugitive
[vim-gitgutter]: https://github.com/airblade/vim-gitgutter
[vim-signify]: https://github.com/mhinz/vim-signify
[virtual lines]: https://github.com/neovim/neovim/pull/15351
[lspsaga.nvim]: https://github.com/glepnir/lspsaga.nvim
