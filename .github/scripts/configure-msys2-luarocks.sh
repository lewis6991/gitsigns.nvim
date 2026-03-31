#!/usr/bin/env bash
set -euo pipefail

luarocks --lua-version=5.1 config variables.LUA /ucrt64/bin/luajit.exe
luarocks --lua-version=5.1 config variables.LUA_BINDIR /ucrt64/bin
luarocks --lua-version=5.1 config variables.LUA_INCDIR /ucrt64/include/luajit-2.1
luarocks --lua-version=5.1 config variables.LUA_LIBDIR /ucrt64/lib
luarocks --lua-version=5.1 config variables.LUALIB libluajit-5.1.dll.a
