local async = require('gitsigns.async')
local log = require('gitsigns.debug.log')
local util = require('gitsigns.util')

local system = require('gitsigns.system').system

--- @type fun(cmd: string[], opts?: vim.SystemOpts): vim.SystemCompleted
local asystem = async.awrap(3, system)

--- @class Gitsigns.Git.JobSpec : vim.SystemOpts
--- @field ignore_error? boolean

--- @param x table<any,any>
--- @return string[]
local function flatten(x)
  local ret = {} --- @type string[]
  for k, v in pairs(x) do
    if type(k) == 'number' then
      if type(v) == 'table' then
        vim.list_extend(ret, flatten(v))
      elseif type(v) == 'string' then
        ret[#ret + 1] = v
      end
    end
  end
  return ret
end

--- @async
--- @param args table<any,any>
--- @param spec? Gitsigns.Git.JobSpec
--- @return string[] stdout, string? stderr, integer code
local function git_command(args, spec)
  spec = spec or {}
  if spec.cwd then
    -- cwd must be a windows path and not a unix path
    spec.cwd = util.cygpath(spec.cwd)
  end

  local cmd = flatten({
    'git',
    '--no-pager',
    '--no-optional-locks',
    '--literal-pathspecs',
    '-c',
    'gc.auto=0', -- Disable auto-packing which emits messages to stderr
    args,
  })

  if spec.text == nil then
    spec.text = true
  end

  -- Fix #895. Only needed for Nvim 0.9 and older
  spec.clear_env = true

  --- @type vim.SystemCompleted
  local obj = asystem(cmd, spec)

  if not spec.ignore_error and obj.code > 0 then
    log.eprintf(
      "Received exit code %d when running command\n'%s':\n%s",
      obj.code,
      table.concat(cmd, ' '),
      obj.stderr
    )
  end

  local stdout_lines = vim.split(obj.stdout or '', '\n')

  if spec.text then
    -- If stdout ends with a newline, then remove the final empty string after
    -- the split
    if stdout_lines[#stdout_lines] == '' then
      stdout_lines[#stdout_lines] = nil
    end
  end

  if log.verbose then
    log.vprintf('%d lines:', #stdout_lines)
    for i = 1, math.min(10, #stdout_lines) do
      log.vprintf('\t%s', stdout_lines[i])
    end
  end

  if obj.stderr == '' then
    obj.stderr = nil
  end

  return stdout_lines, obj.stderr, obj.code
end

return git_command
