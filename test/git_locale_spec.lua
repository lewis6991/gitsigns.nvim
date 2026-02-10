--- @diagnostic disable: global-in-non-module
local helpers = require('test.gs_helpers')

local eq = helpers.eq

local uv = vim.uv or vim.loop ---@diagnostic disable-line: deprecated

helpers.env()

describe('git locale', function()
  --- @type table<string,string?>
  local orig_env

  --- @type string?
  local git_wrapper_dir

  local getenv = uv.os_getenv

  --- @param key string
  --- @param value string?
  local function setenv(key, value)
    if value == nil then
      uv.os_unsetenv(key)
    else
      uv.os_setenv(key, value)
    end
  end

  --- @param cmd string
  --- @return string?
  local function exepath(cmd)
    local path = getenv('PATH') or ''
    for part in path:gmatch('[^:]+') do
      local candidate = part .. '/' .. cmd
      local stat = uv.fs_stat(candidate)
      if stat and stat.type == 'file' then
        return candidate
      end
    end
  end

  --- @param s string
  --- @return string
  local function shellescape(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
  end

  before_each(function()
    orig_env = {
      PATH = getenv('PATH'),
      LANG = getenv('LANG'),
      LC_ALL = getenv('LC_ALL'),
      LC_MESSAGES = getenv('LC_MESSAGES'),
      LANGUAGE = getenv('LANGUAGE'),
      REAL_GIT = getenv('REAL_GIT'),
    }

    local real_git = exepath('git')
    eq(false, real_git == nil or real_git == '', 'git not found in PATH')

    git_wrapper_dir = uv.fs_mkdtemp('/tmp/gitsigns-gitwrap-XXXXXX')
    assert(git_wrapper_dir and git_wrapper_dir ~= '')

    local git_wrapper_path = git_wrapper_dir .. '/git'
    do
      local f = assert(io.open(git_wrapper_path, 'w'))
      f:write(table.concat({
        '#!/bin/sh',
        'set -eu',
        '',
        'real_git="${REAL_GIT:-git}"',
        '',
        'out="$(mktemp)"',
        'err="$(mktemp)"',
        'status=0',
        '"$real_git" "$@" >"$out" 2>"$err" || status=$?',
        '',
        'if [ "$status" -ne 0 ] && [ "${LC_ALL:-}" != "C" ]; then',
        '  if grep -q "fatal: ambiguous argument \'HEAD\'" "$err"; then',
        '    echo "fatal: 参数 \'HEAD\' 不明确" >&2',
        '  else',
        '    cat "$err" >&2',
        '  fi',
        'else',
        '  cat "$err" >&2',
        'fi',
        '',
        'cat "$out"',
        'rm -f "$out" "$err"',
        'exit "$status"',
      }, '\n'))
      f:close()
    end
    uv.fs_chmod(git_wrapper_path, 493)
    -- Simulate a translated git stderr; gitsigns should force `LC_ALL=C` when running git.
    setenv('REAL_GIT', real_git)
    setenv('LANG', 'zh_CN.UTF-8')
    setenv('LC_ALL', 'zh_CN.UTF-8')
    setenv('LC_MESSAGES', nil)
    setenv('LANGUAGE', nil)
    setenv('PATH', git_wrapper_dir .. ':' .. (orig_env.PATH or ''))

    helpers.clear()
  end)

  after_each(function()
    helpers.cleanup()
    if git_wrapper_dir then
      os.execute('rm -rf ' .. shellescape(git_wrapper_dir))
      git_wrapper_dir = nil
    end
    if orig_env then
      for k, v in pairs(orig_env) do
        setenv(k, v)
      end
    end
  end)

  it('attaches in fresh repos regardless of locale', function()
    helpers.setup_test_repo({ no_add = true })

    local config = vim.deepcopy(helpers.test_config)
    config.watch_gitdir = { interval = 100 }
    helpers.setup_gitsigns(config)

    helpers.edit(helpers.test_file)

    helpers.check({
      status = { head = '', added = 18, changed = 0, removed = 0 },
    })

    eq(
      git_wrapper_dir .. '/git',
      helpers.exec_lua(function()
        return vim.fn.exepath('git')
      end)
    )
  end)
end)
