local async = require('gitsigns.async')
local message = require('gitsigns.message')

local cache = require('gitsigns.cache').cache
local api = vim.api

local M = {}

--- Get the commit SHA for the current line
--- @return string?, Gitsigns.CacheEntry?
local function get_commit_sha()
  local bufnr = api.nvim_get_current_buf()
  local bcache = cache[bufnr]
  if not bcache then
    return
  end

  local lnum = api.nvim_win_get_cursor(0)[1]
  local info = bcache:get_blame(lnum)
  if not info then
    message.warn('No blame information available for current line')
    return
  end

  local sha = info.commit.sha
  if not sha or tonumber('0x' .. sha) == 0 then
    message.warn('Current line has no committed changes')
    return
  end

  return sha, bcache
end

--- Copy the commit SHA of the current line to the clipboard
--- Attributes: ~
---     {async}
M.copy_commit_sha = async.create(0, function()
  local sha = get_commit_sha()
  if not sha then
    return
  end

  vim.fn.setreg('+', sha)
  message.info('Copied commit SHA: %s', sha)
end)

--- Open the commit of the current line in the browser
--- Attributes: ~
---     {async}
M.open_commit_in_browser = async.create(0, function()
  local sha, bcache = get_commit_sha()
  if not sha or not bcache then
    return
  end

  -- Try using gh CLI first if available
  local url = require('gitsigns.gh').commit_url(sha, bcache.git_obj.repo.toplevel)

  -- Fallback to parsing remote URL
  if not url then
    local stdout = bcache.git_obj.repo:command(
      { 'config', '--get', 'remote.origin.url' },
      { text = true }
    )
    if stdout and #stdout > 0 then
      local remote_url = vim.trim(stdout[1]):gsub('%.git$', '')
      -- Convert SSH to HTTPS: git@github.com:user/repo -> https://github.com/user/repo
      local host, path = remote_url:match('^git@([^:]+):(.+)$')
      if host and path then
        url = ('https://%s/%s/commit/%s'):format(host, path, sha)
      elseif remote_url:match('^git://') then
        url = ('%s/commit/%s'):format(remote_url:gsub('^git://', 'https://'), sha)
      else
        url = ('%s/commit/%s'):format(remote_url, sha)
      end
    end
  end

  if not url then
    message.error('Could not determine remote URL for repository')
    return
  end

  -- Determine platform-specific open command
  local open_cmd
  if vim.fn.has('mac') == 1 then
    open_cmd = 'open'
  elseif vim.fn.has('unix') == 1 then
    open_cmd = 'xdg-open'
  elseif vim.fn.has('win32') == 1 then
    open_cmd = 'start'
  else
    message.error('Unsupported platform for opening URLs')
    return
  end

  async.schedule()

  vim.fn.system(('%s "%s"'):format(open_cmd, url))
  if vim.v.shell_error == 0 then
    message.info('Opened commit %s in browser', sha:sub(1, 7))
  else
    message.error('Failed to open URL in browser')
  end
end)

return M
