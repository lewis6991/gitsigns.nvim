
local record Cdefs
  xdl_diff: (function(...:any): number)
end

-- C callback
local record CCB
  free: function(CCB)
  set: function(CCB, function)
end

local record ffi
  cdef: function(string)
  new: function(string, ...:any)
  string: function(any, number): string
  gc: function(any, any): any
  C: Cdefs
  cast: function(string, function): CCB
end

return ffi
