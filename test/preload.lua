-- Modules loaded here will not be cleared and reloaded by Busted.
-- Busted started doing this to help provide more isolation.
local global_helpers = require('test.helpers')

-- Bypoass CI behaviour logic
global_helpers.isCI = function(_)
  return false
end

-- v0.9
global_helpers.is_ci = function()
  return false
end

local helpers = require('test.functional.helpers')(nil)
local gs_helpers = require('test.gs_helpers')

