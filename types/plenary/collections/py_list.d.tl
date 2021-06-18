
local record List<T>
  {T}
  contains : function(List<T>, T): boolean
  extend   : function(List<T>, {T})
  slice    : function(List<T>, integer, integer): List<T>
  copy     : function(List<T>): List<T>
  remove   : function(List<T>, integer): List<T>
  insert   : function(List<T>, integer, T)
  push     : function(List<T>, T)
  pop      : function(List<T>): T
  count    : function(List<T>, T): integer
  join     : function(List<T>, string): string
  reverse  : function(List<T>): List<T>
  new      : function({T}): List<T>
end

return List
