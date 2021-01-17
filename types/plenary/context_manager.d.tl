
local record cm
  with: function(thread, function(FILE))
  open: function(string, string): thread
end

return cm
