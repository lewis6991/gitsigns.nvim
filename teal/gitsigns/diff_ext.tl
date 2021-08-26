local git = require('gitsigns.git')

local gs_hunks = require("gitsigns.hunks")
local Hunk = gs_hunks.Hunk
local util = require('gitsigns.util')
local scheduler = require('plenary.async.util').scheduler

local record M
  -- Async function
  run_diff: function({string}, {string}, string, boolean): {Hunk}
end

local function write_to_file(path: string, text: {string})
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

M.run_diff = function(
  text_cmp: {string},
  text_buf: {string},
  diff_algo: string,
  indent_heuristic: boolean
): {Hunk}
  local results: {Hunk} = {}

  if not util.is_unix then
    -- tmpname must not be called in a callback on windows
    scheduler()
  end

  local file_buf = util.tmpname()..'_buf'
  local file_cmp = util.tmpname()..'_cmp'

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
  --   warning: LF will be replace by CRLF in <temp file>.
  --   The file will have its original line endings in your working directory.
  --
  -- We can safely ignore the warning, we turn it off by passing the '-c
  -- "core.safecrlf=false"' argument to git-diff.

  local out = git.command{
    '-c', 'core.safecrlf=false',
    'diff',
    '--color=never',
    '--'..(indent_heuristic and '' or 'no-')..'indent-heuristic',
    '--diff-algorithm='..diff_algo,
    '--patch-with-raw',
    '--unified=0',
    file_cmp,
    file_buf,
  }

  for _, line in ipairs(out) do
    if vim.startswith(line, '@@') then
      table.insert(results, gs_hunks.parse_diff_line(line))
    elseif #results > 0 then
      table.insert(results[#results].lines, line)
    end
  end

  os.remove(file_buf)
  os.remove(file_cmp)
  return results
end

return M
