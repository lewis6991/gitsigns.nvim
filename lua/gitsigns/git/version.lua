local async = require('gitsigns.async')
local gs_config = require('gitsigns.config')

local log = require('gitsigns.debug.log')
local err = require('gitsigns.message').error
local system = require('gitsigns.system').system

local M = {}

--- @type fun(cmd: string[], opts?: vim.SystemOpts): vim.SystemCompleted
local asystem = async.awrap(3, system)

--- @class (exact) Gitsigns.Version
--- @field major integer
--- @field minor integer
--- @field patch integer

--- @param version string
--- @return Gitsigns.Version
local function parse_version(version)
  assert(version:match('%d+%.%d+%.%w+'), 'Invalid git version: ' .. version)
  local ret = {}
  local parts = vim.split(version, '%.')
  ret.major = assert(tonumber(parts[1]))
  ret.minor = assert(tonumber(parts[2]))

  if parts[3] == 'GIT' then
    ret.patch = 0
  else
    local patch_ver = vim.split(parts[3], '-')
    ret.patch = assert(tonumber(patch_ver[1]))
  end

  return ret
end

--- @async
local function set_version()
  local version = gs_config.config._git_version
  if version ~= 'auto' then
    local ok, ret = pcall(parse_version, version)
    if ok then
      M.version = ret
    else
      err(ret --[[@as string]])
    end
    return
  end

  --- @type vim.SystemCompleted
  local obj = asystem({ 'git', '--version' })
  async.scheduler()

  local line = vim.split(obj.stdout or '', '\n')[1]
  if not line then
    err("Unable to detect git version as 'git --version' failed to return anything")
    log.eprint(obj.stderr)
    return
  end

  -- Sometime 'git --version' returns an empty string (#948)
  if log.assert(type(line) == 'string', 'Unexpected output: ' .. line) then
    return
  end

  if log.assert(vim.startswith(line, 'git version'), 'Unexpected output: ' .. line) then
    return
  end

  local parts = vim.split(line, '%s+')
  M.version = parse_version(parts[3])
end

--- @async
--- Usage: check_version{2,3}
--- @param major? integer
--- @param minor? integer
--- @param patch? integer
--- @return boolean
function M.check(major, minor, patch)
  if not M.version then
    set_version()
  end

  if not M.version then
    return false
  elseif not major or not minor then
    return false
  elseif M.version.major < major then
    return false
  elseif minor and M.version.minor < minor then
    return false
  elseif patch and M.version.patch < patch then
    return false
  end
  return true
end

return M
