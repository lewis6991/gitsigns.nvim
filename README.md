# gitsigns.nvim

[![CI](https://github.com/lewis6991/gitsigns.nvim/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/lewis6991/gitsigns.nvim/actions?query=workflow%3ACI)
[![Version](https://img.shields.io/github/v/release/lewis6991/gitsigns.nvim)](https://github.com/lewis6991/gitsigns.nvim/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Gitter](https://badges.gitter.im/gitsigns-nvim/community.svg)](https://gitter.im/gitsigns-nvim/community?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge)
[![Dotfyle](https://dotfyle.com/plugins/lewis6991/gitsigns.nvim/shield)](https://dotfyle.com/plugins/lewis6991/gitsigns.nvim)


Deep buffer integration for Git

## 👀 Preview

| Hunk Actions | Line Blame |
| --- | ----------- |
| <img src="https://raw.githubusercontent.com/lewis6991/media/main/gitsigns_actions.gif" width="450em"/> | <img src="https://raw.githubusercontent.com/lewis6991/media/main/gitsigns_blame.gif" width="450em"/> |

## ✨ Features

<details>
  <summary><strong>Signs</strong></summary>

  - Adds signs to the sign column to indicate added, changed, and deleted lines.

    ![image](https://github.com/user-attachments/assets/e49ea0bf-c427-41fb-a67f-77c2d413a7cf)

  - Supports different signs for staged changes.

    ![image](https://github.com/user-attachments/assets/28a3e286-96fa-478c-93a3-8028f9bd7123)

  - Add counts to signs.

    ![image](https://github.com/user-attachments/assets/d007b924-6811-44ea-b936-d8da4dc00b68)


</details>

<details>
  <summary><strong>Hunk Actions</strong></summary>

  - Stage/unstage hunks with `:Gitsigns stage_hunk`.
  - Reset hunks with `:Gitsigns reset_hunk`.
  - Also works on partial hunks in visual mode.
  - Preview hunks inline with `:Gitsigns preview_hunk_inline`

    ![image](https://github.com/user-attachments/assets/60acd664-f4a8-4737-ba65-969f1efa7971)

  - Preview hunks in popup with `:Gitsigns preview_hunk`

    ![image](https://github.com/user-attachments/assets/d2a9b801-5857-4054-80a8-195d111f4e8c)

  - Navigate between hunks with `:Gitsigns nav_hunk next/prev`.

</details>

<details>
  <summary><strong>Blame</strong></summary>

  - Show blame of current buffer using `:Gitsigns blame`.

    ![image](https://github.com/user-attachments/assets/7d881e94-6e16-4f98-a526-7e785b11acf9)

  - Show blame information for the current line in popup with `:Gitsigns blame_line`.

    ![image](https://github.com/user-attachments/assets/03ff7557-b538-4cd1-9478-f893bf7e616e)

  - Show blame information for the current line in virtual text.

    ![image](https://github.com/user-attachments/assets/0c79e880-6a6d-4c3f-aa62-33f734725cfd)

    - Enable with `setup({ current_line_blame = true })`.
    - Toggle with `:Gitsigns toggle_current_line_blame`

</details>

<details>
  <summary><strong>Diff</strong></summary>

  - Change the revision for the signs with `:Gitsigns change_base <REVISION>`.
  - Show the diff of the current buffer with the index or any revision
    with `:Gitsigns diffthis <REVISION>`.
  - Show intra-line word-diff in the buffer.

    ![image](https://github.com/user-attachments/assets/409a1f91-5cee-404b-8b12-66b7db3ecac7)

    - Enable with `setup({ word_diff = true })`.
    - Toggle with `:Gitsigns toggle_word_diff`.

</details>

<details>
  <summary><strong>Show hunks Quickfix/Location List</strong></summary>

  - Set the quickfix/location list with changes with `:Gitsign setqflist/setloclist`.

    ![image](https://github.com/user-attachments/assets/c17001a5-b9cf-4a00-9891-5b130c0b4745)

    Can show hunks for:
    - whole repository (`target=all`)
    - attached buffers (`target=attached`)
    - a specific buffer (`target=[integer]`).

</details>

<details>
  <summary><strong>Text Object</strong></summary>

  - Select hunks as a text object.
  - Can use `vim.keymap.set({'o', 'x'}, 'ih', '<Cmd>Gitsigns select_hunk<CR>')`

</details>

<details>
  <summary><strong>Status Line Integration</strong></summary>

  Use `b:gitsigns_status` or `b:gitsigns_status_dict`. `b:gitsigns_status` is
  formatted using `config.status_formatter`. `b:gitsigns_status_dict` is a
  dictionary with the keys `added`, `removed`, `changed` and `head`.

  Example:
  ```viml
  set statusline+=%{get(b:,'gitsigns_status','')}
  ```

  For the current branch use the variable `b:gitsigns_head`.

</details>

<details>
  <summary><strong>Show different revisions of buffers</strong></summary>

  - Use `:Gitsigns show <REVISION>` to `:edit` the current buffer at `<REVISION>`

</details>

## 📋 Requirements

- Neovim >= 0.9.0

> [!TIP]
> If your version of Neovim is too old, then you can use a past [release].

> [!WARNING]
> If you are running a development version of Neovim (aka `master`), then
> breakage may occur if your build is behind latest.

- Newish version of git. Older versions may not work with some features.

## 🛠️ Installation & Usage

Install using your package manager of choice. No setup required.

Optional configuration can be passed to the setup function. Here is an example
with most of the default settings:

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
    style = 'minimal',
    relative = 'cursor',
    row = 0,
    col = 1
  },
}
```

For information on configuring Neovim via lua please see [nvim-lua-guide].

### 🎹 Keymaps

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
    map('n', '<leader>tw', gitsigns.toggle_word_diff)

    -- Text object
    map({'o', 'x'}, 'ih', gitsigns.select_hunk)
  end
}
```
## 🔗 Plugin Integrations

### [vim-fugitive]

When viewing revisions of a file (via `:0Gclog` for example), Gitsigns will attach to the fugitive buffer with the base set to the commit immediately before the commit of that revision.
This means the signs placed in the buffer reflect the changes introduced by that revision of the file.

### [trouble.nvim]

If installed and enabled (via `config.trouble`; defaults to true if installed), `:Gitsigns setqflist` or `:Gitsigns setloclist` will open Trouble instead of Neovim's built-in quickfix or location list windows.

## 🚫 Non-Goals

### Implement every feature in [vim-fugitive]

This plugin is actively developed and by one of the most well regarded vim plugin developers.
Gitsigns will only implement features of this plugin if: it is simple, or, the technologies leveraged by Gitsigns (LuaJIT, Libuv, Neovim's API, etc) can provide a better experience.

### Support for other VCS

There aren't any active developers of this plugin who use other kinds of VCS, so adding support for them isn't feasible.
However a well written PR with a commitment of future support could change this.

## 🔌 Similar plugins

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
