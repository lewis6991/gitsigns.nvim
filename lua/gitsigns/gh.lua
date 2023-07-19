local async = require('gitsigns.async')
local log = require('gitsigns.debug.log')
local subprocess = require('gitsigns.subprocess')

--- @class GitHub.PrInfo
--- @field url string
--- @field author {login: string, name: string}
--- @field mergedAt string
--- @field number string
--- @field title string
--- @field is_github? boolean

local M = {}

local GH_NOT_FOUND_ERROR = "Could not find 'gh' command. Is the gh-cli package installed?";


local gh_command = function(args)
  if vim.fn.executable('gh') then
    return async.wait(2, subprocess.run_job, { command = 'gh', args = args });
  end

  return {};
end

--- Requests a list of GitHub PRs associated with the given commit SHA
---
--- @param sha string The commit SHA
---
--- @return GitHub.PrInfo[]? : Array of PR object
M.associated_prs = function(sha)
  local _, _, stdout, stderr = gh_command({
    'pr', 'list',
    '--search', sha,
    '--state', 'merged',
    '--json', 'url,author,title,number,mergedAt',
  })

  if stderr then
    log.eprintf("Received stderr when running 'gh pr list' command:\n%s", stderr)
  end

  local empty_set_len = 2;

  if type(stdout) == string and #stdout > empty_set_len then
    return vim.json.decode(stdout);
  end

  return nil;
end

--- Returns the last PR associated with the commit
---
--- @param sha string The commit SHA
---
--- @return GitHub.PrInfo? : The latest PR associated with the commit or nil
M.get_last_associated_pr = function(sha)
  local prs = M.associated_prs(sha);
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
