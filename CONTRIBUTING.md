## Requirements

- [Luarocks](https://luarocks.org/)
    - `brew install luarocks`

## Generating docs

Most of the documentation is handwritten however the documentation for the configuration is generated from `lua/gitsigns/config.lua` which contains the configuration schema.
The documentation is generated with the lua script `gen_help.lua` which has been developed just enough to handle the current configuration schema so from time to time this script might need small improvements to handle new features but for the most part it works.

The documentation can be updated with:

```bash
make gen_help
```

## Testsuite

The testsuite uses the same framework as Neovims funcitonaltest suite.
This is just busted with lots of helper code to create headless neovim instances which are controlled via RPC.

To run the testsuite:

```bash
make test
```

## LSP

Gitsigns maintains its own `.luarc.json`, however it depends on certain environment variables to be defined.

- `$NVIM_TYPES_DIR`: should point to a local copy of [folke/neodev.nvim/types](https://github.com/folke/neodev.nvim/tree/main/types/nightly)

- `$NVIM_RUNTIME`: This can be found by running `echo $VIMRUNTIME` in Nvim.

