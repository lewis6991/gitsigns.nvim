## Requirements

- [Luarocks](https://luarocks.org/)
    - `brew install luarocks`

## Generating docs

Most of the documentation is handwritten however the documentation for the configuration is generated from `lua/gitsigns/config.lua` which contains the configuration schema.
The documentation is generated with the lua script `gen_help.lua` which has been developed just enough to handle the current configuration schema so from time to time this script might need small improvements to handle new features but for the most part it works.

The documentation can be updated with:

```
make gen_help
```

Note: The default Make target is to run both `tl-build` and `gen_help` so it's often easier to just run `make` to update generated files (or even `:make` from within Neovim).

## Testsuite

The testsuite uses the same framework as Neovims funcitonaltest suite.
This is just busted with lots of helper code to create headless neovim instances which are controlled via RPC.

The first time you run the testsuite, Neovim will be compiled from source (this is the Neovim build that tests will use).
This is arguably a little bit overkill for such a plugin but it allows:

- Easily running tests with Neovim master
- Tests which check the screen state (essential for a UI plugin)

To run the testsuite:

```
make test
```
