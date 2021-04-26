---
name: Bug report
about: Create a report to help us improve
title: ''
labels: bug
assignees: ''

---

**Describe the bug**
A clear and concise description of what the bug is.

**To Reproduce**

init.vim:

```vim
let $PLUGIN_DIRECTORY = '~/.config/nvim/bundle'
set runtimepath^=$PLUGIN_DIRECTORY/plenary.nvim
set runtimepath^=$PLUGIN_DIRECTORY/gitsigns.nvim

lua << EOF
require('gitsigns').setup {
  debug_mode = true, -- You must add this to enable debug messages
  -- config
}
EOF
```

Steps to reproduce the behavior:
1. Go to '...'
2. Run '....'
3. See error

**Observed output**
Error messages, logs, etc

Include the output of `:Gitsigns debug_messages`. If you think it's relevant maybe also provide the output of `:Gitsigns dump_cache`.

**Screenshots**
If applicable, add screenshots to help explain your problem or to capture error messages.

**Additional context**
System: Mac, Linux (including dist), Windows
Neovim version: xxx
