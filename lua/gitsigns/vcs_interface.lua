local gs_hunks = require("gitsigns.hunks")
local Hunk = gs_hunks.Hunk

local GJobSpec = {}









local Vcs = {BlameInfo = {}, Version = {}, Repo = {}, FileProps = {}, Obj = {}, }























































































local M = {}




M.new_vcs = function()
   local self = setmetatable({}, { __index = Vcs })
   return self
end

return M
