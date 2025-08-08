local async = require('gitsigns.async')
local log = require('gitsigns.debug.log')
local system = require('gitsigns.system').system

--- @type async fun(cmd: string[], opts?: vim.SystemOpts): vim.SystemCompleted
local asystem = async.wrap(3, system)

--- @class gitsigns.gh.PrInfo
--- @field url string
--- @field number string

local M = {}

--- @async
--- @param args string[]
--- @param cwd? string
--- @return table? json
local function gh_cmd(args, cwd)
  if vim.fn.executable('gh') == 0 then
    log.eprintf('Could not find gh command')
    return
  end
  --- @diagnostic disable-next-line: param-type-not-match EmmyLuaLs/emmylua-analyzer-rust#594
  local obj = asystem({ 'gh', unpack(args) }, { cwd = cwd })
  --- @cast obj.stderr -?

  if obj.code ~= 0 then
    if
      obj.stderr:match(
        'none of the git remotes configured for this repository point to a known GitHub host'
      )
    then
      return
    end
    log.eprintf(
      "Error running 'gh %s', code=%d: %s",
      table.concat(args, ' '),
      obj.code,
      obj.stderr or '[no stderr]'
    )
    return
  end

  return vim.json.decode(assert(obj.stdout))
end

--- @async
--- @param cwd? string
--- @return string? : The URL of the current repository
local function repo_url(cwd)
  local res = gh_cmd({ 'repo', 'view', '--json', 'url' }, cwd)
  if res then
    return res.url
  end
end

--- @async
function M.commit_url(sha, cwd)
  local url = repo_url(cwd)
  if url then
    return ('%s/commit/%s'):format(url, sha)
  end
end

--- Requests a list of GitHub PRs associated with the given commit SHA
--- @async
--- @param sha string
--- @param cwd string
--- @return gitsigns.gh.PrInfo[]? : Array of PR object
local function associated_prs(sha, cwd)
  return gh_cmd({
    'pr',
    'list',
    '--search',
    sha,
    '--state',
    'merged',
    '--json',
    'url,number',
  }, cwd)
end

--- @async
--- @param sha string
--- @param toplevel string
--- @return Gitsigns.LineSpec
function M.create_pr_linespec(sha, toplevel)
  local ret = {} --- @type Gitsigns.LineSpec
  local prs = associated_prs(sha, toplevel)
  if prs and next(prs) then
    ret[#ret + 1] = { '(', 'Title' }
    for i, pr in ipairs(prs) do
      ret[#ret + 1] = { ('#%s'):format(pr.number), 'Title', pr.url }
      if i < #prs then
        ret[#ret + 1] = { ', ', 'NormalFloat' }
      end
    end
    ret[#ret + 1] = { ') ', 'Title' }
  end
  return ret
end

return M
