local a = require('plenary/async_lib/async')

local record M
  type future0 = function(function())
  type future1 = function<A1>(function(A1))
  type future2 = function<A1,A2>(function(A1,A2))
  type future3 = function<A1,A2,A3>(function(A1,A2,A3))
  type future4 = function<A1,A2,A3,A4>(function(A1,A2,A3,A4))

  await0: function(future0): ()
  await1: function<A1>(future1<A1>): A1
  await2: function<A1,A2>(future2<A1,A2>): A1,A2
  await3: function<A1,A2,A3>(future3<A1,A2,A3>): A1,A2,A3
  await4: function<A1,A2,A3,A4>(future4<A1,A2,A3,A4>): A1,A2,A3,A4
  await_main: function()

  type async_fun0 = function(): future0
  type async_fun0_1 = function<R1>(): future1<R1>
  type async_fun0_2 = function<R1,R2>(): future2<R1,R2>
  type async_fun0_3 = function<R1,R2,R3>(): future3<R1,R2,R3>
  type async_fun0_4 = function<R1,R2,R3,R4>(): future4<R1,R2,R3,R4>
  type async_fun1 = function<A1>(A1): future0
  type async_fun1_1 = function<A1,R1>(A1): future1<R1>
  type async_fun1_2 = function<A1,R1,R2>(A1): future2<R1,R2>
  type async_fun1_3 = function<A1,R1,R2,R3>(A1): future3<R1,R2,R3>
  type async_fun1_4 = function<A1,R1,R2,R3,R4>(A1): future4<R1,R2,R3,R4>
  type async_fun2 = function<A1,A2>(A1,A2): future0
  type async_fun2_1 = function<A1,A2,R1>(A1,A2): future1<R1>
  type async_fun2_2 = function<A1,A2,R1,R2>(A1,A2): future2<R1,R2>
  type async_fun2_3 = function<A1,A2,R1,R2,R3>(A1,A2): future3<R1,R2,R3>
  type async_fun2_4 = function<A1,A2,R1,R2,R3,R4>(A1,A2): future4<R1,R2,R3,R4>
  type async_fun3 = function<A1,A2,A3>(A1,A2,A3): future0
  type async_fun3_1 = function<A1,A2,A3,R1>(A1,A2,A3): future1<R1>
  type async_fun3_2 = function<A1,A2,A3,R1,R2>(A1,A2,A3): future2<R1,R2>
  type async_fun3_3 = function<A1,A2,A3,R1,R2,R3>(A1,A2,A3): future3<R1,R2,R3>
  type async_fun3_4 = function<A1,A2,A3,R1,R2,R3,R4>(A1,A2,A3): future4<R1,R2,R3,R4>
  type async_fun4 = function<A1,A2,A3,A4>(A1,A2,A3,A4): future0
  type async_fun4_1 = function<A1,A2,A3,A4,R1>(A1,A2,A3,A4): future1<R1>
  type async_fun4_2 = function<A1,A2,A3,A4,R1,R2>(A1,A2,A3,A4): future2<R1,R2>
  type async_fun4_3 = function<A1,A2,A3,A4,R1,R2,R3>(A1,A2,A3,A4): future3<R1,R2,R3>
  type async_fun4_4 = function<A1,A2,A3,A4,R1,R2,R3,R4>(A1,A2,A3,A4): future4<R1,R2,R3,R4>

  wrap0: function(function(function())): async_fun0
  wrap0_1: function<R1>(function(function(R1))): async_fun0_1<R1>
  wrap0_2: function<R1,R2>(function(function(R1,R2))): async_fun0_2<R1,R2>
  wrap0_3: function<R1,R2,R3>(function(function(R1,R2,R3))): async_fun0_3<R1,R2,R3>
  wrap0_4: function<R1,R2,R3,R4>(function(function(R1,R2,R3,R4))): async_fun0_4<R1,R2,R3,R4>
  wrap1: function<A1>(function(A1,function())): async_fun1<A1>
  wrap1_1: function<A1,R1>(function(A1,function(R1))): async_fun1_1<A1,R1>
  wrap1_2: function<A1,R1,R2>(function(A1,function(R1,R2))): async_fun1_2<A1,R1,R2>
  wrap1_3: function<A1,R1,R2,R3>(function(A1,function(R1,R2,R3))): async_fun1_3<A1,R1,R2,R3>
  wrap1_4: function<A1,R1,R2,R3,R4>(function(A1,function(R1,R2,R3,R4))): async_fun1_4<A1,R1,R2,R3,R4>
  wrap2: function<A1,A2>(function(A1,A2,function())): async_fun2<A1,A2>
  wrap2_1: function<A1,A2,R1>(function(A1,A2,function(R1))): async_fun2_1<A1,A2,R1>
  wrap2_2: function<A1,A2,R1,R2>(function(A1,A2,function(R1,R2))): async_fun2_2<A1,A2,R1,R2>
  wrap2_3: function<A1,A2,R1,R2,R3>(function(A1,A2,function(R1,R2,R3))): async_fun2_3<A1,A2,R1,R2,R3>
  wrap2_4: function<A1,A2,R1,R2,R3,R4>(function(A1,A2,function(R1,R2,R3,R4))): async_fun2_4<A1,A2,R1,R2,R3,R4>
  wrap3: function<A1,A2,A3>(function(A1,A2,A3,function())): async_fun3<A1,A2,A3>
  wrap3_1: function<A1,A2,A3,R1>(function(A1,A2,A3,function(R1))): async_fun3_1<A1,A2,A3,R1>
  wrap3_2: function<A1,A2,A3,R1,R2>(function(A1,A2,A3,function(R1,R2))): async_fun3_2<A1,A2,A3,R1,R2>
  wrap3_3: function<A1,A2,A3,R1,R2,R3>(function(A1,A2,A3,function(R1,R2,R3))): async_fun3_3<A1,A2,A3,R1,R2,R3>
  wrap3_4: function<A1,A2,A3,R1,R2,R3,R4>(function(A1,A2,A3,function(R1,R2,R3,R4))): async_fun3_4<A1,A2,A3,R1,R2,R3,R4>
  wrap4: function<A1,A2,A3,A4>(function(A1,A2,A3,A4,function())): async_fun4<A1,A2,A3,A4>
  wrap4_1: function<A1,A2,A3,A4,R1>(function(A1,A2,A3,A4,function(R1))): async_fun4_1<A1,A2,A3,A4,R1>
  wrap4_2: function<A1,A2,A3,A4,R1,R2>(function(A1,A2,A3,A4,function(R1,R2))): async_fun4_2<A1,A2,A3,A4,R1,R2>
  wrap4_3: function<A1,A2,A3,A4,R1,R2,R3>(function(A1,A2,A3,A4,function(R1,R2,R3))): async_fun4_3<A1,A2,A3,A4,R1,R2,R3>
  wrap4_4: function<A1,A2,A3,A4,R1,R2,R3,R4>(function(A1,A2,A3,A4,function(R1,R2,R3,R4))): async_fun4_4<A1,A2,A3,A4,R1,R2,R3,R4>

  async0: function(function(): ()): async_fun0
  async0_1: function<R1>(function(): R1): async_fun0_1<R1>
  async0_2: function<R1,R2>(function(): R1,R2): async_fun0_2<R1,R2>
  async0_3: function<R1,R2,R3>(function(): R1,R2,R3): async_fun0_3<R1,R2,R3>
  async0_4: function<R1,R2,R3,R4>(function(): R1,R2,R3,R4): async_fun0_4<R1,R2,R3,R4>
  async1: function<A1>(function(A1): ()): async_fun1<A1>
  async1_1: function<A1,R1>(function(A1): R1): async_fun1_1<A1,R1>
  async1_2: function<A1,R1,R2>(function(A1): R1,R2): async_fun1_2<A1,R1,R2>
  async1_3: function<A1,R1,R2,R3>(function(A1): R1,R2,R3): async_fun1_3<A1,R1,R2,R3>
  async1_4: function<A1,R1,R2,R3,R4>(function(A1): R1,R2,R3,R4): async_fun1_4<A1,R1,R2,R3,R4>
  async2: function<A1,A2>(function(A1,A2): ()): async_fun2<A1,A2>
  async2_1: function<A1,A2,R1>(function(A1,A2): R1): async_fun2_1<A1,A2,R1>
  async2_2: function<A1,A2,R1,R2>(function(A1,A2): R1,R2): async_fun2_2<A1,A2,R1,R2>
  async2_3: function<A1,A2,R1,R2,R3>(function(A1,A2): R1,R2,R3): async_fun2_3<A1,A2,R1,R2,R3>
  async2_4: function<A1,A2,R1,R2,R3,R4>(function(A1,A2): R1,R2,R3,R4): async_fun2_4<A1,A2,R1,R2,R3,R4>
  async3: function<A1,A2,A3>(function(A1,A2,A3): ()): async_fun3<A1,A2,A3>
  async3_1: function<A1,A2,A3,R1>(function(A1,A2,A3): R1): async_fun3_1<A1,A2,A3,R1>
  async3_2: function<A1,A2,A3,R1,R2>(function(A1,A2,A3): R1,R2): async_fun3_2<A1,A2,A3,R1,R2>
  async3_3: function<A1,A2,A3,R1,R2,R3>(function(A1,A2,A3): R1,R2,R3): async_fun3_3<A1,A2,A3,R1,R2,R3>
  async3_4: function<A1,A2,A3,R1,R2,R3,R4>(function(A1,A2,A3): R1,R2,R3,R4): async_fun3_4<A1,A2,A3,R1,R2,R3,R4>
  async4: function<A1,A2,A3,A4>(function(A1,A2,A3,A4): ()): async_fun4<A1,A2,A3,A4>
  async4_1: function<A1,A2,A3,A4,R1>(function(A1,A2,A3,A4): R1): async_fun4_1<A1,A2,A3,A4,R1>
  async4_2: function<A1,A2,A3,A4,R1,R2>(function(A1,A2,A3,A4): R1,R2): async_fun4_2<A1,A2,A3,A4,R1,R2>
  async4_3: function<A1,A2,A3,A4,R1,R2,R3>(function(A1,A2,A3,A4): R1,R2,R3): async_fun4_3<A1,A2,A3,A4,R1,R2,R3>
  async4_4: function<A1,A2,A3,A4,R1,R2,R3,R4>(function(A1,A2,A3,A4): R1,R2,R3,R4): async_fun4_4<A1,A2,A3,A4,R1,R2,R3,R4>

  void: function(function): function
  void_async: function(function): function

end

M.void = a.void
M.void_async = function(func: function): function
  return M.void(a.async(func))
end

M.await0 = a.await as function(M.future0): ()
M.await1 = a.await as function<A1>(M.future1<A1>): A1
M.await2 = a.await as function<A1,A2>(M.future2<A1,A2>): A1,A2
M.await3 = a.await as function<A1,A2,A3>(M.future3<A1,A2,A3>): A1,A2,A3
M.await4 = a.await as function<A1,A2,A3,A4>(M.future4<A1,A2,A3,A4>): A1,A2,A3,A4
M.await_main = function()
  a.await(a.scheduler())
end

M.wrap0 = function(func: function(function())): M.async_fun0
  return a.wrap(func, 1) as M.async_fun0
end
M.wrap0_1 = function<R1>(func: function(function(R1))): M.async_fun0_1<R1>
  return a.wrap(func, 1) as M.async_fun0_1<R1>
end
M.wrap0_2 = function<R1,R2>(func: function(function(R1,R2))): M.async_fun0_2<R1,R2>
  return a.wrap(func, 1) as M.async_fun0_2<R1,R2>
end
M.wrap0_3 = function<R1,R2,R3>(func: function(function(R1,R2,R3))): M.async_fun0_3<R1,R2,R3>
  return a.wrap(func, 1) as M.async_fun0_3<R1,R2,R3>
end
M.wrap0_4 = function<R1,R2,R3,R4>(func: function(function(R1,R2,R3,R4))): M.async_fun0_4<R1,R2,R3,R4>
  return a.wrap(func, 1) as M.async_fun0_4<R1,R2,R3,R4>
end
M.wrap1 = function<A1>(func: function(A1,function())): M.async_fun1<A1>
  return a.wrap(func, 2) as M.async_fun1<A1>
end
M.wrap1_1 = function<A1,R1>(func: function(A1,function(R1))): M.async_fun1_1<A1,R1>
  return a.wrap(func, 2) as M.async_fun1_1<A1,R1>
end
M.wrap1_2 = function<A1,R1,R2>(func: function(A1,function(R1,R2))): M.async_fun1_2<A1,R1,R2>
  return a.wrap(func, 2) as M.async_fun1_2<A1,R1,R2>
end
M.wrap1_3 = function<A1,R1,R2,R3>(func: function(A1,function(R1,R2,R3))): M.async_fun1_3<A1,R1,R2,R3>
  return a.wrap(func, 2) as M.async_fun1_3<A1,R1,R2,R3>
end
M.wrap1_4 = function<A1,R1,R2,R3,R4>(func: function(A1,function(R1,R2,R3,R4))): M.async_fun1_4<A1,R1,R2,R3,R4>
  return a.wrap(func, 2) as M.async_fun1_4<A1,R1,R2,R3,R4>
end
M.wrap2 = function<A1,A2>(func: function(A1,A2,function())): M.async_fun2<A1,A2>
  return a.wrap(func, 3) as M.async_fun2<A1,A2>
end
M.wrap2_1 = function<A1,A2,R1>(func: function(A1,A2,function(R1))): M.async_fun2_1<A1,A2,R1>
  return a.wrap(func, 3) as M.async_fun2_1<A1,A2,R1>
end
M.wrap2_2 = function<A1,A2,R1,R2>(func: function(A1,A2,function(R1,R2))): M.async_fun2_2<A1,A2,R1,R2>
  return a.wrap(func, 3) as M.async_fun2_2<A1,A2,R1,R2>
end
M.wrap2_3 = function<A1,A2,R1,R2,R3>(func: function(A1,A2,function(R1,R2,R3))): M.async_fun2_3<A1,A2,R1,R2,R3>
  return a.wrap(func, 3) as M.async_fun2_3<A1,A2,R1,R2,R3>
end
M.wrap2_4 = function<A1,A2,R1,R2,R3,R4>(func: function(A1,A2,function(R1,R2,R3,R4))): M.async_fun2_4<A1,A2,R1,R2,R3,R4>
  return a.wrap(func, 3) as M.async_fun2_4<A1,A2,R1,R2,R3,R4>
end
M.wrap3 = function<A1,A2,A3>(func: function(A1,A2,A3,function())): M.async_fun3<A1,A2,A3>
  return a.wrap(func, 4) as M.async_fun3<A1,A2,A3>
end
M.wrap3_1 = function<A1,A2,A3,R1>(func: function(A1,A2,A3,function(R1))): M.async_fun3_1<A1,A2,A3,R1>
  return a.wrap(func, 4) as M.async_fun3_1<A1,A2,A3,R1>
end
M.wrap3_2 = function<A1,A2,A3,R1,R2>(func: function(A1,A2,A3,function(R1,R2))): M.async_fun3_2<A1,A2,A3,R1,R2>
  return a.wrap(func, 4) as M.async_fun3_2<A1,A2,A3,R1,R2>
end
M.wrap3_3 = function<A1,A2,A3,R1,R2,R3>(func: function(A1,A2,A3,function(R1,R2,R3))): M.async_fun3_3<A1,A2,A3,R1,R2,R3>
  return a.wrap(func, 4) as M.async_fun3_3<A1,A2,A3,R1,R2,R3>
end
M.wrap3_4 = function<A1,A2,A3,R1,R2,R3,R4>(func: function(A1,A2,A3,function(R1,R2,R3,R4))): M.async_fun3_4<A1,A2,A3,R1,R2,R3,R4>
  return a.wrap(func, 4) as M.async_fun3_4<A1,A2,A3,R1,R2,R3,R4>
end
M.wrap4 = function<A1,A2,A3,A4>(func: function(A1,A2,A3,A4,function())): M.async_fun4<A1,A2,A3,A4>
  return a.wrap(func, 5) as M.async_fun4<A1,A2,A3,A4>
end
M.wrap4_1 = function<A1,A2,A3,A4,R1>(func: function(A1,A2,A3,A4,function(R1))): M.async_fun4_1<A1,A2,A3,A4,R1>
  return a.wrap(func, 5) as M.async_fun4_1<A1,A2,A3,A4,R1>
end
M.wrap4_2 = function<A1,A2,A3,A4,R1,R2>(func: function(A1,A2,A3,A4,function(R1,R2))): M.async_fun4_2<A1,A2,A3,A4,R1,R2>
  return a.wrap(func, 5) as M.async_fun4_2<A1,A2,A3,A4,R1,R2>
end
M.wrap4_3 = function<A1,A2,A3,A4,R1,R2,R3>(func: function(A1,A2,A3,A4,function(R1,R2,R3))): M.async_fun4_3<A1,A2,A3,A4,R1,R2,R3>
  return a.wrap(func, 5) as M.async_fun4_3<A1,A2,A3,A4,R1,R2,R3>
end
M.wrap4_4 = function<A1,A2,A3,A4,R1,R2,R3,R4>(func: function(A1,A2,A3,A4,function(R1,R2,R3,R4))): M.async_fun4_4<A1,A2,A3,A4,R1,R2,R3,R4>
  return a.wrap(func, 5) as M.async_fun4_4<A1,A2,A3,A4,R1,R2,R3,R4>
end

M.async0 = a.async as function(function(): ()): M.async_fun0
M.async0_1 = a.async as function<R1>(function(): R1): M.async_fun0_1<R1>
M.async0_2 = a.async as function<R1,R2>(function(): R1,R2): M.async_fun0_2<R1,R2>
M.async0_3 = a.async as function<R1,R2,R3>(function(): R1,R2,R3): M.async_fun0_3<R1,R2,R3>
M.async0_4 = a.async as function<R1,R2,R3,R4>(function(): R1,R2,R3,R4): M.async_fun0_4<R1,R2,R3,R4>
M.async1 = a.async as function<A1>(function(A1): ()): M.async_fun1<A1>
M.async1_1 = a.async as function<A1,R1>(function(A1): R1): M.async_fun1_1<A1,R1>
M.async1_2 = a.async as function<A1,R1,R2>(function(A1): R1,R2): M.async_fun1_2<A1,R1,R2>
M.async1_3 = a.async as function<A1,R1,R2,R3>(function(A1): R1,R2,R3): M.async_fun1_3<A1,R1,R2,R3>
M.async1_4 = a.async as function<A1,R1,R2,R3,R4>(function(A1): R1,R2,R3,R4): M.async_fun1_4<A1,R1,R2,R3,R4>
M.async2 = a.async as function<A1,A2>(function(A1,A2): ()): M.async_fun2<A1,A2>
M.async2_1 = a.async as function<A1,A2,R1>(function(A1,A2): R1): M.async_fun2_1<A1,A2,R1>
M.async2_2 = a.async as function<A1,A2,R1,R2>(function(A1,A2): R1,R2): M.async_fun2_2<A1,A2,R1,R2>
M.async2_3 = a.async as function<A1,A2,R1,R2,R3>(function(A1,A2): R1,R2,R3): M.async_fun2_3<A1,A2,R1,R2,R3>
M.async2_4 = a.async as function<A1,A2,R1,R2,R3,R4>(function(A1,A2): R1,R2,R3,R4): M.async_fun2_4<A1,A2,R1,R2,R3,R4>
M.async3 = a.async as function<A1,A2,A3>(function(A1,A2,A3): ()): M.async_fun3<A1,A2,A3>
M.async3_1 = a.async as function<A1,A2,A3,R1>(function(A1,A2,A3): R1): M.async_fun3_1<A1,A2,A3,R1>
M.async3_2 = a.async as function<A1,A2,A3,R1,R2>(function(A1,A2,A3): R1,R2): M.async_fun3_2<A1,A2,A3,R1,R2>
M.async3_3 = a.async as function<A1,A2,A3,R1,R2,R3>(function(A1,A2,A3): R1,R2,R3): M.async_fun3_3<A1,A2,A3,R1,R2,R3>
M.async3_4 = a.async as function<A1,A2,A3,R1,R2,R3,R4>(function(A1,A2,A3): R1,R2,R3,R4): M.async_fun3_4<A1,A2,A3,R1,R2,R3,R4>
M.async4 = a.async as function<A1,A2,A3,A4>(function(A1,A2,A3,A4): ()): M.async_fun4<A1,A2,A3,A4>
M.async4_1 = a.async as function<A1,A2,A3,A4,R1>(function(A1,A2,A3,A4): R1): M.async_fun4_1<A1,A2,A3,A4,R1>
M.async4_2 = a.async as function<A1,A2,A3,A4,R1,R2>(function(A1,A2,A3,A4): R1,R2): M.async_fun4_2<A1,A2,A3,A4,R1,R2>
M.async4_3 = a.async as function<A1,A2,A3,A4,R1,R2,R3>(function(A1,A2,A3,A4): R1,R2,R3): M.async_fun4_3<A1,A2,A3,A4,R1,R2,R3>
M.async4_4 = a.async as function<A1,A2,A3,A4,R1,R2,R3,R4>(function(A1,A2,A3,A4): R1,R2,R3,R4): M.async_fun4_4<A1,A2,A3,A4,R1,R2,R3,R4>

return M
