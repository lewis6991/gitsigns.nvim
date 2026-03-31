#!/usr/bin/env bash
set -euo pipefail

chmod +x "$GITHUB_WORKSPACE/.luarocks/bin/luarocks" \
  "$GITHUB_WORKSPACE/.luarocks/bin/luarocks-admin"

github_output=$(cygpath --unix "$GITHUB_OUTPUT")
printf 'bin=%s\n' "$(cygpath --unix "$GITHUB_WORKSPACE/.luarocks/bin")" >> "$github_output"
