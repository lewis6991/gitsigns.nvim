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
  -- config
}
EOF

```

Steps to reproduce the behavior:
1. Go to '...'
2. Click on '....'
3. Scroll down to '....'
4. See error

**Observed output**
Error messages, logs, etc

**Screenshots**
If applicable, add screenshots to help explain your problem or to capture error messages.

**Additional context**
System: Mac, Linux, Windows
Neovim version: xxx
