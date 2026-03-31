# Testing Guidelines

Read this file before broad test changes, CI debugging, or test-heavy work.

## Main Commands

- In the sandbox, always raise the file descriptor limit before functional
  tests: `ulimit -n 1024; make test ...`
- `ulimit -n 1024; make test [FILTER=pattern]`: run the functional suite with
  the default Neovim target.
- `ulimit -n 1024; make test-010`, `ulimit -n 1024; make test-011`,
  `ulimit -n 1024; make test-012`, `ulimit -n 1024; make test-nightly`: run
  the suite against the supported Neovim versions.
- `make build`: format Lua sources and regenerate docs before committing.
- `make doc` / `make doc-check`: regenerate help docs and fail on drift.
- `make emmylua-check`: run the optional static analysis pass.

## Test Selection

- Add or update tests for risky, non-obvious, or broad changes.
- Small localized fixes can skip dedicated regression coverage when existing
  tests already cover the behavior well enough.
- When Neovim internals are touched, run the version matrix and at least check
  `make test-010 && make test-nightly`.
- Keep tests deterministic by guarding optional Git features.
