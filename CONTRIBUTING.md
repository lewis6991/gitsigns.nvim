## Requirements

- [Luarocks](https://luarocks.org/)
    - `brew install luarocks`

## Writing Teal

 **Do not edit files in the lua dir**.

Gitsigns is implemented in teal which is essentially lua+types.
The teal source files are generated into lua files and must be checked in together when making changes.
CI will enforce this.

Once you have made changes in teal, the corresponding lua files can be built with:

```
make tl-build
```

## Generating docs

Most of the documentation is handwritten however the documentation for the configuration is generated from `teal/gitsigns/config.tl` which contains the configuration schema.
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

## [Diagnostic-ls](https://github.com/iamcco/diagnostic-languageserver) config for teal

```
require('lspconfig').diagnosticls.setup{
  filetypes = {'teal'},
  init_options = {
    filetypes = {teal = {'tealcheck'}},
    linters = {
      tealcheck = {
        sourceName = "tealcheck",
        command = "tl",
        args = {'check', '%file'},
        isStdout = false, isStderr = true,
        rootPatterns = {"tlconfig.lua", ".git"},
        formatPattern = {
          '^([^:]+):(\\d+):(\\d+): (.+)$', {
            sourceName = 1, sourceNameFilter = true,
            line = 2, column = 3, message = 4
          }
        }
      }
    }
  }
}
```

## [null-ls.nvim](https://github.com/jose-elias-alvarez/null-ls.nvim) config for teal

```
local null_ls = require("null-ls")

null_ls.config {sources = {
  null_ls.builtins.diagnostics.teal
}}
require("lspconfig")["null-ls"].setup {}
```
