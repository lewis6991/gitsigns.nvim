local _MODREV, _SPECREV = 'scm', '-1'

rockspec_format = "3.0"
package = 'gitsigns.nvim'
version = _MODREV .. _SPECREV

description = {
  summary = 'Git signs written in pure lua',
  detailed = [[
    Super fast git decorations implemented purely in lua/teal.
  ]],
  homepage = 'http://github.com/lewis6991/gitsigns.nvim',
  license = 'MIT/X11',
  labels = { 'neovim' }
}

dependencies = {
  'lua == 5.1',
  'plenary.nvim',
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
  modules = {
    ['gitsigns']                       = 'lua/gitsigns.lua',
    ['gitsigns.actions']               = 'lua/gitsigns/actions.lua',
    ['gitsigns.cache']                 = 'lua/gitsigns/cache.lua',
    ['gitsigns.config']                = 'lua/gitsigns/config.lua',
    ['gitsigns.current_line_blame']    = 'lua/gitsigns/current_line_blame.lua',
    ['gitsigns.debounce']              = 'lua/gitsigns/debounce.lua',
    ['gitsigns.debug']                 = 'lua/gitsigns/debug.lua',
    ['gitsigns.diff_ext']              = 'lua/gitsigns/diff_ext.lua',
    ['gitsigns.diff_int']              = 'lua/gitsigns/diff_int.lua',
    ['gitsigns.diff_int.xdl_diff_ffi'] = 'lua/gitsigns/diff_int/xdl_diff_ffi.lua',
    ['gitsigns.git']                   = 'lua/gitsigns/git.lua',
    ['gitsigns.highlight']             = 'lua/gitsigns/highlight.lua',
    ['gitsigns.hunks']                 = 'lua/gitsigns/hunks.lua',
    ['gitsigns.manager']               = 'lua/gitsigns/manager.lua',
    ['gitsigns.mappings']              = 'lua/gitsigns/mappings.lua',
    ['gitsigns.message']               = 'lua/gitsigns/message.lua',
    ['gitsigns.popup']                 = 'lua/gitsigns/popup.lua',
    ['gitsigns.repeat']                = 'lua/gitsigns/repeat.lua',
    ['gitsigns.signs']                 = 'lua/gitsigns/signs.lua',
    ['gitsigns.status']                = 'lua/gitsigns/status.lua',
    ['gitsigns.subprocess']            = 'lua/gitsigns/subprocess.lua',
    ['gitsigns.util']                  = 'lua/gitsigns/util.lua',
  },
  copy_directories = {
    'doc'
  }
}
