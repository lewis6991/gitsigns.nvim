local config = require('gitsigns.config').config
local git_diff = require('gitsigns.git').diff

local gs_hunks = require('gitsigns.hunks')
local util = require('gitsigns.util')
local scheduler = require('gitsigns.async').scheduler

local M = {}
-- Async function

--- @param path string
--- @param text string[]
local function write_to_file(path, text)
  local f, err = io.open(path, 'wb')
  if f == nil then
    error(err)
  end
  for _, l in ipairs(text) do
    f:write(l)
    f:write('\n')
  end
  f:close()
end

--- @async
--- @param text_cmp string[]
--- @param text_buf string[]
--- @return Gitsigns.Hunk.Hunk[]
function M.run_diff(text_cmp, text_buf)
  local results = {} --- @type Gitsigns.Hunk.Hunk[]

  -- tmpname must not be called in a callback
  if vim.in_fast_event() then
    scheduler()
  end

  local file_buf = util.tmpname()
  local file_cmp = util.tmpname()

  write_to_file(file_buf, text_buf)
  write_to_file(file_cmp, text_cmp)

  -- Taken from gitgutter, diff.vim:
  --
  -- If a file has CRLF line endings and git's core.autocrlf is true, the file
  -- in git's object store will have LF line endings. Writing it out via
  -- git-show will produce a file with LF line endings.
  --
  -- If this last file is one of the files passed to git-diff, git-diff will
  -- convert its line endings to CRLF before diffing -- which is what we want
  -- but also by default outputs a warning on stderr.
  --
  --    warning: LF will be replace by CRLF in <temp file>.
  --    The file will have its original line endings in your working directory.
  --
  -- We can safely ignore the warning, we turn it off by passing the '-c
  -- "core.safecrlf=false"' argument to git-diff.

  local opts = config.diff_opts
  local out = git_diff(file_cmp, file_buf, opts.indent_heuristic, opts.algorithm)

  for _, line in ipairs(out) do
    if vim.startswith(line, '@@') then
      results[#results + 1] = gs_hunks.parse_diff_line(line)
    elseif #results > 0 then
      local r = results[#results]
      if line:sub(1, 1) == '-' then
        r.removed.lines[#r.removed.lines + 1] = line:sub(2)
      elseif line:sub(1, 1) == '+' then
        r.added.lines[#r.added.lines + 1] = line:sub(2)
      end
    end
  end

  os.remove(file_buf)
  os.remove(file_cmp)
  return results
end

return M
