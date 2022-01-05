local Vcs = require('gitsigns.vcs_interface').new_vcs()
local git = require('gitsigns.git')

local cache: {string:Vcs} = {}

local record M
  vcs_for_path: function(string): Vcs
end

M.vcs_for_path = function(path: string): Vcs
  local value_from_cache = cache[path]
  if value_from_cache then
    return value_from_cache
  end

  if git.is_inside_worktree(path) then
    cache[path] = git
    return git
  end

  return nil
end

return M
