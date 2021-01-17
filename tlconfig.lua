return {
  skip_compat53 = true,
  preload_modules = {
    'types',
    'gitsigns/types',
  },
  include_dir = {
    "types",
    "teal",
  },
  exclude = {
    'gitsigns/types.tl'
  },
  source_dir = 'teal',
  build_dir = "lua",
}
