
local record util
  type fun1 = function <A1>   (A1)
  type fun2 = function <A1,A2>(A1,A2)

  sleep: function(integer)
  scheduler: function()

  will_block: function<A1>   (fun1 <A1>   ): fun1<A1>
  will_block: function<A1,A2>(fun2 <A1,A2>): fun2<A1,A2>
end

return util
