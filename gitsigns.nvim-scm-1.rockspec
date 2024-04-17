local _MODREV, _SPECREV = 'scm', '-1'

rockspec_format = "3.0"
package = 'gitsigns.nvim'
version = _MODREV .. _SPECREV

description = {
  summary = 'Git signs written in pure lua',
  detailed = [[
    Super fast git decorations implemented purely in Lua.
  ]],
  homepage = 'http://github.com/lewis6991/gitsigns.nvim',
  license = 'MIT/X11',
  labels = { 'neovim' }
}

dependencies = {
  'lua == 5.1',
}

source = {
  url = 'http://github.com/lewis6991/gitsigns.nvim/archive/v' .. _MODREV .. '.zip',
  dir = 'gitsigns.nvim-' .. _MODREV,
}

if _MODREV == 'scm' then
  source = {
    url = 'git://github.com/lewis6991/gitsigns.nvim',
  }
end

build = {
  type = 'builtin',
  copy_directories = {
    'doc'
  }
}
