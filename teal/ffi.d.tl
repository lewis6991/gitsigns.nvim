
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
  load: function(string): any
  new: function(string, ...:any): any
  string: function(any, number): string
  gc: function<T>(T, function): T
  C: Cdefs
  cast: function(string, any): CCB
  errno: function(): integer
  copy: function
  metatype: function(string, any)
end

return ffi
