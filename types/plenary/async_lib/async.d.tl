local record Async
  type future  = function             (function)
  type future0 = function             (function())
  type future1 = function<A1>         (function(A1))
  type future2 = function<A1,A2>      (function(A1,A2))
  type future3 = function<A1,A2,A3>   (function(A1,A2,A3))
  type future4 = function<A1,A2,A3,A4>(function(A1,A2,A3,A4))

  type async_fun0   = function                           ()            : future0
  type async_fun0_1 = function <R1>                      ()            : future1<R1>
  type async_fun0_2 = function <R1,R2>                   ()            : future2<R1,R2>
  type async_fun0_3 = function <R1,R2,R3>                ()            : future3<R1,R2,R3>
  type async_fun0_4 = function <R1,R2,R3,R4>             ()            : future4<R1,R2,R3,R4>
  type async_fun1   = function <A1>                      (A1)          : future0
  type async_fun1_1 = function <A1,R1>                   (A1)          : future1<R1>
  type async_fun1_2 = function <A1,R1,R2>                (A1)          : future2<R1,R2>
  type async_fun1_3 = function <A1,R1,R2,R3>             (A1)          : future3<R1,R2,R3>
  type async_fun1_4 = function <A1,R1,R2,R3,R4>          (A1)          : future4<R1,R2,R3,R4>
  type async_fun2   = function <A1,A2>                   (A1,A2)       : future0
  type async_fun2_1 = function <A1,A2,R1>                (A1,A2)       : future1<R1>
  type async_fun2_2 = function <A1,A2,R1,R2>             (A1,A2)       : future2<R1,R2>
  type async_fun2_3 = function <A1,A2,R1,R2,R3>          (A1,A2)       : future3<R1,R2,R3>
  type async_fun2_4 = function <A1,A2,R1,R2,R3,R4>       (A1,A2)       : future4<R1,R2,R3,R4>
  type async_fun3   = function <A1,A2,A3>                (A1,A2,A3)    : future0
  type async_fun3_1 = function <A1,A2,A3,R1>             (A1,A2,A3)    : future1<R1>
  type async_fun3_2 = function <A1,A2,A3,R1,R2>          (A1,A2,A3)    : future2<R1,R2>
  type async_fun3_3 = function <A1,A2,A3,R1,R2,R3>       (A1,A2,A3)    : future3<R1,R2,R3>
  type async_fun3_4 = function <A1,A2,A3,R1,R2,R3,R4>    (A1,A2,A3)    : future4<R1,R2,R3,R4>
  type async_fun4   = function <A1,A2,A3,A4>             (A1,A2,A3,A4) : future0
  type async_fun4_1 = function <A1,A2,A3,A4,R1>          (A1,A2,A3,A4) : future1<R1>
  type async_fun4_2 = function <A1,A2,A3,A4,R1,R2>       (A1,A2,A3,A4) : future2<R1,R2>
  type async_fun4_3 = function <A1,A2,A3,A4,R1,R2,R3>    (A1,A2,A3,A4) : future3<R1,R2,R3>
  type async_fun4_4 = function <A1,A2,A3,A4,R1,R2,R3,R4> (A1,A2,A3,A4) : future4<R1,R2,R3,R4>

  await: function              (future0             ): ()
  await: function<A1>          (future1<A1>         ): A1
  await: function<A1,A2>       (future2<A1,A2>      ): A1,A2
  await: function<A1,A2,A3>    (future3<A1,A2,A3>   ): A1,A2,A3
  await: function<A1,A2,A3,A4> (future4<A1,A2,A3,A4>): A1,A2,A3,A4

  async: function                         (function()            : ()         ): async_fun0
  async: function<R1>                     (function()            : R1         ): async_fun0_1 <R1>
  async: function<R1,R2>                  (function()            : R1,R2      ): async_fun0_2 <R1,R2>
  async: function<R1,R2,R3>               (function()            : R1,R2,R3   ): async_fun0_3 <R1,R2,R3>
  async: function<R1,R2,R3,R4>            (function()            : R1,R2,R3,R4): async_fun0_4 <R1,R2,R3,R4>
  async: function<A1>                     (function(A1)          : ()         ): async_fun1   <A1>
  async: function<A1,R1>                  (function(A1)          : R1         ): async_fun1_1 <A1,R1>
  async: function<A1,R1,R2>               (function(A1)          : R1,R2      ): async_fun1_2 <A1,R1,R2>
  async: function<A1,R1,R2,R3>            (function(A1)          : R1,R2,R3   ): async_fun1_3 <A1,R1,R2,R3>
  async: function<A1,R1,R2,R3,R4>         (function(A1)          : R1,R2,R3,R4): async_fun1_4 <A1,R1,R2,R3,R4>
  async: function<A1,A2>                  (function(A1,A2)       : ()         ): async_fun2   <A1,A2>
  async: function<A1,A2,R1>               (function(A1,A2)       : R1         ): async_fun2_1 <A1,A2,R1>
  async: function<A1,A2,R1,R2>            (function(A1,A2)       : R1,R2      ): async_fun2_2 <A1,A2,R1,R2>
  async: function<A1,A2,R1,R2,R3>         (function(A1,A2)       : R1,R2,R3   ): async_fun2_3 <A1,A2,R1,R2,R3>
  async: function<A1,A2,R1,R2,R3,R4>      (function(A1,A2)       : R1,R2,R3,R4): async_fun2_4 <A1,A2,R1,R2,R3,R4>
  async: function<A1,A2,A3>               (function(A1,A2,A3)    : ()         ): async_fun3   <A1,A2,A3>
  async: function<A1,A2,A3,R1>            (function(A1,A2,A3)    : R1         ): async_fun3_1 <A1,A2,A3,R1>
  async: function<A1,A2,A3,R1,R2>         (function(A1,A2,A3)    : R1,R2      ): async_fun3_2 <A1,A2,A3,R1,R2>
  async: function<A1,A2,A3,R1,R2,R3>      (function(A1,A2,A3)    : R1,R2,R3   ): async_fun3_3 <A1,A2,A3,R1,R2,R3>
  async: function<A1,A2,A3,R1,R2,R3,R4>   (function(A1,A2,A3)    : R1,R2,R3,R4): async_fun3_4 <A1,A2,A3,R1,R2,R3,R4>
  async: function<A1,A2,A3,A4>            (function(A1,A2,A3,A4) : ()         ): async_fun4   <A1,A2,A3,A4>
  async: function<A1,A2,A3,A4,R1>         (function(A1,A2,A3,A4) : R1         ): async_fun4_1 <A1,A2,A3,A4,R1>
  async: function<A1,A2,A3,A4,R1,R2>      (function(A1,A2,A3,A4) : R1,R2      ): async_fun4_2 <A1,A2,A3,A4,R1,R2>
  async: function<A1,A2,A3,A4,R1,R2,R3>   (function(A1,A2,A3,A4) : R1,R2,R3   ): async_fun4_3 <A1,A2,A3,A4,R1,R2,R3>
  async: function<A1,A2,A3,A4,R1,R2,R3,R4>(function(A1,A2,A3,A4) : R1,R2,R3,R4): async_fun4_4 <A1,A2,A3,A4,R1,R2,R3,R4>

  wrap: function                         (function(            function())           , integer): async_fun0
  wrap: function<R1>                     (function(            function(R1))         , integer): async_fun0_1 <R1>
  wrap: function<R1,R2>                  (function(            function(R1,R2))      , integer): async_fun0_2 <R1,R2>
  wrap: function<R1,R2,R3>               (function(            function(R1,R2,R3))   , integer): async_fun0_3 <R1,R2,R3>
  wrap: function<R1,R2,R3,R4>            (function(            function(R1,R2,R3,R4)), integer): async_fun0_4 <R1,R2,R3,R4>
  wrap: function<A1>                     (function(A1,         function())           , integer): async_fun1   <A1>
  wrap: function<A1,R1>                  (function(A1,         function(R1))         , integer): async_fun1_1 <A1,R1>
  wrap: function<A1,R1,R2>               (function(A1,         function(R1,R2))      , integer): async_fun1_2 <A1,R1,R2>
  wrap: function<A1,R1,R2,R3>            (function(A1,         function(R1,R2,R3))   , integer): async_fun1_3 <A1,R1,R2,R3>
  wrap: function<A1,R1,R2,R3,R4>         (function(A1,         function(R1,R2,R3,R4)), integer): async_fun1_4 <A1,R1,R2,R3,R4>
  wrap: function<A1,A2>                  (function(A1,A2,      function())           , integer): async_fun2   <A1,A2>
  wrap: function<A1,A2,R1>               (function(A1,A2,      function(R1))         , integer): async_fun2_1 <A1,A2,R1>
  wrap: function<A1,A2,R1,R2>            (function(A1,A2,      function(R1,R2))      , integer): async_fun2_2 <A1,A2,R1,R2>
  wrap: function<A1,A2,R1,R2,R3>         (function(A1,A2,      function(R1,R2,R3))   , integer): async_fun2_3 <A1,A2,R1,R2,R3>
  wrap: function<A1,A2,R1,R2,R3,R4>      (function(A1,A2,      function(R1,R2,R3,R4)), integer): async_fun2_4 <A1,A2,R1,R2,R3,R4>
  wrap: function<A1,A2,A3>               (function(A1,A2,A3,   function())           , integer): async_fun3   <A1,A2,A3>
  wrap: function<A1,A2,A3,R1>            (function(A1,A2,A3,   function(R1))         , integer): async_fun3_1 <A1,A2,A3,R1>
  wrap: function<A1,A2,A3,R1,R2>         (function(A1,A2,A3,   function(R1,R2))      , integer): async_fun3_2 <A1,A2,A3,R1,R2>
  wrap: function<A1,A2,A3,R1,R2,R3>      (function(A1,A2,A3,   function(R1,R2,R3))   , integer): async_fun3_3 <A1,A2,A3,R1,R2,R3>
  wrap: function<A1,A2,A3,R1,R2,R3,R4>   (function(A1,A2,A3,   function(R1,R2,R3,R4)), integer): async_fun3_4 <A1,A2,A3,R1,R2,R3,R4>
  wrap: function<A1,A2,A3,A4>            (function(A1,A2,A3,A4,function())           , integer): async_fun4   <A1,A2,A3,A4>
  wrap: function<A1,A2,A3,A4,R1>         (function(A1,A2,A3,A4,function(R1))         , integer): async_fun4_1 <A1,A2,A3,A4,R1>
  wrap: function<A1,A2,A3,A4,R1,R2>      (function(A1,A2,A3,A4,function(R1,R2))      , integer): async_fun4_2 <A1,A2,A3,A4,R1,R2>
  wrap: function<A1,A2,A3,A4,R1,R2,R3>   (function(A1,A2,A3,A4,function(R1,R2,R3))   , integer): async_fun4_3 <A1,A2,A3,A4,R1,R2,R3>
  wrap: function<A1,A2,A3,A4,R1,R2,R3,R4>(function(A1,A2,A3,A4,function(R1,R2,R3,R4)), integer): async_fun4_4 <A1,A2,A3,A4,R1,R2,R3,R4>

  scheduler: future
  execute: function
  void: function(function): function
  run: function
end

return Async
