local M = {}

local tests = {}
local after_each_hooks = {}
local uv = vim.uv or vim.loop ---@diagnostic disable-line: deprecated

local function pack_len(...)
  return { n = select('#', ...), ... }
end

local function unpack_len(t, first)
  return unpack(t, first or 1, t.n or table.maxn(t))
end

local function format_cmd(cmd)
  return table.concat(cmd, ' ')
end

function M.it(name, fn)
  tests[#tests + 1] = { name = name, fn = fn }
end

function M.after_each(fn)
  after_each_hooks[#after_each_hooks + 1] = fn
end

function M.eq(expected, actual, msg)
  if not vim.deep_equal(expected, actual) then
    error(msg or ('Expected %s, got %s'):format(vim.inspect(expected), vim.inspect(actual)), 2)
  end
end

function M.ok(value, msg)
  if not value then
    error(msg or 'Expected a truthy value', 2)
  end
end

function M.trim(value)
  return vim.trim(value)
end

--- @param path string
--- @param mode? 'unix'|'windows'|'mixed'
--- @return string
function M.cygpath(path, mode)
  return M.trim(M.system({ 'cygpath', '--absolute', '--' .. (mode or 'windows'), path }).stdout)
end

function M.wait_for(predicate, opts)
  opts = opts or {}
  local timeout = opts.timeout or 2000
  local interval = opts.interval or 10

  local done = vim.wait(timeout, function()
    local ok, result = pcall(predicate)
    return ok and result
  end, interval, true)

  if not done then
    error(opts.msg or ('Timed out after %dms'):format(timeout), 2)
  end
end

function M.system(cmd, opts)
  if not vim.system then
    error('vim.system is required for the windows smoke harness', 2)
  end

  opts = vim.tbl_extend('force', { text = true }, opts or {})

  local obj = vim.system(cmd, opts):wait(opts.timeout)
  if obj.code ~= 0 then
    error(
      ('command failed (%d): %s\nstdout:\n%s\nstderr:\n%s'):format(
        obj.code,
        format_cmd(cmd),
        obj.stdout or '',
        obj.stderr or ''
      ),
      2
    )
  end

  return obj
end

function M.join(...)
  return vim.fs.joinpath(...)
end

function M.edit(path)
  vim.cmd.edit(vim.fn.fnameescape(path))
end

function M.mkdir(path)
  if vim.fn.isdirectory(path) == 1 then
    return
  end
  local ok = vim.fn.mkdir(path, 'p')
  M.ok(ok == 1, ('Failed to create directory %s'):format(path))
end

function M.write_file(path, lines)
  local parent = vim.fs.dirname(path)
  if parent then
    M.mkdir(parent)
  end
  vim.fn.writefile(lines, path)
end

function M.cleanup(path)
  if path and path ~= '' then
    vim.fn.delete(path, 'rf')
  end
end

function M.tmpdir()
  local path = vim.fn.tempname()
  M.cleanup(path)
  M.mkdir(path)
  return uv.fs_realpath(path) or path
end

function M.run()
  local failures = 0

  for _, test in ipairs(tests) do
    local ok, err = xpcall(test.fn, debug.traceback)
    if ok then
      print(('ok - %s'):format(test.name))
    else
      failures = failures + 1
      print(('not ok - %s'):format(test.name))
      print(err)
    end

    for _, hook in ipairs(after_each_hooks) do
      pcall(hook)
    end
    pcall(vim.cmd, 'silent! %bwipeout!')
  end

  return failures
end

return M
