local async = require('gitsigns.async')
local log = require('gitsigns.debug.log')
local system = require('gitsigns.system').system

local uv = vim.uv or vim.loop ---@diagnostic disable-line: deprecated

--- @type async fun(cmd: string[], opts?: vim.SystemOpts): vim.SystemCompleted
local asystem = async.wrap(3, system)

--- @class gitsigns.gh.PrInfo
--- @field url string
--- @field number string

--- @class (exact) Gitsigns.Gh.RepoMeta
--- @field nameWithOwner string
--- @field url string?

local M = {}

local session_pr_cache = {} --- @type table<string, table<string, gitsigns.gh.PrInfo[]|false>>
local repo_meta_cache = {} --- @type table<string, Gitsigns.Gh.RepoMeta|false>

--- @param cwd string
--- @return string
local function repo_key(cwd)
  return uv.fs_realpath(cwd) or cwd
end

local function log_gh_error(fmt, ...)
  pcall(log.eprintf, fmt, ...)
end

--- @async
--- @param args string[]
--- @param cwd? string
--- @return table? json
local function gh_cmd(args, cwd)
  if vim.fn.executable('gh') == 0 then
    log_gh_error('Could not find gh command')
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
    log_gh_error(
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
--- @param cwd string
--- @return Gitsigns.Gh.RepoMeta?
local function repo_meta(cwd)
  local key = repo_key(cwd)
  local cached = repo_meta_cache[key]
  if cached ~= nil then
    return cached or nil
  end

  local res = gh_cmd({ 'repo', 'view', '--json', 'nameWithOwner,url' }, cwd)
  if type(res) ~= 'table' or type(res.nameWithOwner) ~= 'string' then
    repo_meta_cache[key] = false
    return
  end

  --- @type Gitsigns.Gh.RepoMeta
  local meta = {
    nameWithOwner = res.nameWithOwner,
    url = type(res.url) == 'string' and res.url or nil,
  }
  repo_meta_cache[key] = meta
  return meta
end

--- @async
--- @param query string
--- @param fields table<string, string>
--- @param cwd string
--- @return table? data
local function gh_graphql(query, fields, cwd)
  local args = { 'api', 'graphql', '-f', 'query=' .. query }
  for name, value in pairs(fields) do
    args[#args + 1] = '-F'
    args[#args + 1] = ('%s=%s'):format(name, value)
  end

  local res = gh_cmd(args, cwd)
  if type(res) == 'table' then
    return res.data
  end
end

--- @param nodes any
--- @return gitsigns.gh.PrInfo[]|false
local function normalize_graphql_prs(nodes)
  local prs = {} --- @type gitsigns.gh.PrInfo[]
  if type(nodes) == 'table' then
    for _, pr in ipairs(nodes) do
      if pr.mergedAt ~= vim.NIL and pr.mergedAt ~= nil then
        prs[#prs + 1] = {
          number = tostring(pr.number),
          url = pr.url,
        }
      end
    end
  end

  return next(prs) and prs or false
end

--- @param pulls any
--- @return gitsigns.gh.PrInfo[]|false|nil
local function normalize_rest_prs(pulls)
  if type(pulls) ~= 'table' then
    return
  end

  local prs = {} --- @type gitsigns.gh.PrInfo[]
  for _, pr in ipairs(pulls) do
    if pr.merged_at ~= vim.NIL and pr.merged_at ~= nil then
      prs[#prs + 1] = {
        number = tostring(pr.number),
        url = pr.html_url or pr.url,
      }
    end
  end

  return next(prs) and prs or false
end

--- @async
--- @param shas string[]
--- @param owner string
--- @param name string
--- @param cwd string
--- @return table<string, gitsigns.gh.PrInfo[]|false>
local function lookup_associated_prs_rest_many(shas, owner, name, cwd)
  local ret = {} --- @type table<string, gitsigns.gh.PrInfo[]|false>
  for _, sha in ipairs(shas) do
    local pulls = gh_cmd({ 'api', ('repos/%s/%s/commits/%s/pulls'):format(owner, name, sha) }, cwd)
    local prs = normalize_rest_prs(pulls)
    if prs ~= nil then
      -- A failed REST request is inconclusive; don't turn it into a stable
      -- "no PRs" result.
      ret[sha] = prs
    end
  end
  return ret
end

--- @param shas string[]
--- @return string
local function build_associated_prs_query(shas)
  -- Build one aliased commit lookup per SHA so visible history rows can share
  -- a single GraphQL round-trip instead of spawning a `gh` search per commit.
  local vars = {
    '$owner:String!',
    '$name:String!',
  }
  local fields = {} --- @type string[]

  for i = 1, #shas do
    vars[#vars + 1] = ('$sha%d:GitObjectID!'):format(i)
    fields[#fields + 1] = ([[
      c%d: object(oid:$sha%d) {
        ... on Commit {
          associatedPullRequests(first:10) {
            nodes {
              number
              url
              mergedAt
            }
          }
        }
      }
    ]]):format(i, i)
  end

  return ('query(%s) { repository(owner:$owner, name:$name) { %s } }'):format(
    table.concat(vars, ', '),
    table.concat(fields, ' ')
  )
end

--- Requests GitHub PRs associated with multiple commit SHAs.
--- @async
--- @param shas string[]
--- @param cwd string
--- @return table<string, gitsigns.gh.PrInfo[]|false>?
local function lookup_associated_prs_many(shas, cwd)
  if #shas == 0 then
    return {}
  end

  local meta = repo_meta(cwd)
  if not meta then
    return
  end

  local owner, name = meta.nameWithOwner:match('^([^/]+)/(.+)$')
  if not owner or not name then
    return
  end

  local fields = {
    owner = owner,
    name = name,
  }

  for i, sha in ipairs(shas) do
    fields[('sha%d'):format(i)] = sha
  end

  local data = gh_graphql(build_associated_prs_query(shas), fields, cwd)
  local repo = type(data) == 'table' and data.repository or nil
  if type(repo) ~= 'table' then
    return lookup_associated_prs_rest_many(shas, owner, name, cwd)
  end

  local ret = {} --- @type table<string, gitsigns.gh.PrInfo[]|false>
  for i, sha in ipairs(shas) do
    local obj = repo[('c%d'):format(i)]
    local nodes = type(obj) == 'table'
        and type(obj.associatedPullRequests) == 'table'
        and obj.associatedPullRequests.nodes
      or nil

    ret[sha] = normalize_graphql_prs(nodes)
  end

  return ret
end

--- @async
function M.commit_url(sha, cwd)
  if not cwd then
    return
  end

  local meta = repo_meta(cwd)
  if meta and meta.url then
    return ('%s/commit/%s'):format(meta.url, sha)
  end
end

--- Requests a list of GitHub PRs associated with the given commit SHA
--- @async
--- @param shas string[]
--- @param cwd string
--- @return table<string, gitsigns.gh.PrInfo[]|false>?
function M.associated_prs_many(shas, cwd)
  local ret = {} --- @type table<string, gitsigns.gh.PrInfo[]|false>
  local missing = {} --- @type string[]
  local cache_key = repo_key(cwd)
  local repo_cache = session_pr_cache[cache_key]

  for _, sha in ipairs(shas) do
    local prs = repo_cache and repo_cache[sha]
    if prs ~= nil then
      ret[sha] = prs
    else
      missing[#missing + 1] = sha
    end
  end

  if #missing == 0 then
    return ret
  end

  local fetched = lookup_associated_prs_many(missing, cwd)
  if not fetched then
    return next(ret) and ret or nil
  end

  for _, sha in ipairs(missing) do
    local prs = fetched[sha]
    if prs ~= nil then
      if not repo_cache then
        repo_cache = {}
        session_pr_cache[cache_key] = repo_cache
      end
      repo_cache[sha] = prs
      ret[sha] = prs
    end
  end

  return ret
end

--- @async
--- @param sha string
--- @param cwd string
--- @return gitsigns.gh.PrInfo[]?
function M.associated_prs(sha, cwd)
  local prs = M.associated_prs_many({ sha }, cwd)
  if prs then
    local pr = prs[sha]
    return pr ~= false and pr or nil
  end
end

--- @async
--- @param sha string
--- @param toplevel string
--- @return Gitsigns.LineSpec
function M.create_pr_linespec(sha, toplevel)
  local ret = {} --- @type Gitsigns.LineSpec
  local prs = M.associated_prs(sha, toplevel)
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
