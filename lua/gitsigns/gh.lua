local async = require('gitsigns.async')
local subprocess = require('gitsigns.subprocess')
local log = require('gitsigns.debug.log')


--- @class GitHub.PrInfo
--- @field url string
--- @field author {login: string, name: string}
--- @field mergedAt string
--- @field number string
--- @field title string
--- @field is_github? boolean

local M = {}

--- Requests a list of GitHub PRs associated with the given commit SHA
---
--- @param toplevel string The URL to the repository
--- @param sha string The commit SHA
---
--- @return GitHub.PrInfo[]? : Array of PR object
M.associated_prs = function(toplevel, sha)
  local _, _, stdout, stderr = async.wait(2, subprocess.run_job, {
    command = 'gh',
    cwd = toplevel,
    args = {
      'pr', 'list',
      '--search', sha,
      '--state', 'merged',
      '--json', 'url,author,title,number,mergedAt',
    },
  })

  if stderr then
    log.eprintf("Received stderr when running 'gh pr list' command:\n%s", stderr)

    return {};
  end

  return vim.json.decode(stdout);
end

--- Returns the last PR associated with the commit
---
--- @param toplevel string The URL to the repository
--- @param sha string The commit SHA
---
--- @return GitHub.PrInfo? : The latest PR associated with the commit or nil
M.get_last_associated_pr = function(toplevel, sha)
  local prs = M.associated_prs(toplevel, sha);
  --- @type GitHub.PrInfo?
  local last_pr = nil;

  if prs then
    for _, pr in ipairs(prs) do
      local pr_number = tonumber(pr.number);
      local last_pr_number = last_pr and tonumber(last_pr.number) or 0;

      if pr_number > last_pr_number then
        last_pr = pr
      end
    end
  end

  return last_pr;
end

return M
