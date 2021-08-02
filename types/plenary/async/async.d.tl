local record Async
  type fun0   = function                           ()
  type fun0_1 = function <R1>                      ()            : R1
  type fun0_2 = function <R1,R2>                   ()            : R1,R2
  type fun0_3 = function <R1,R2,R3>                ()            : R1,R2,R3
  type fun0_4 = function <R1,R2,R3,R4>             ()            : R1,R2,R3,R4
  type fun1   = function <A1>                      (A1)
  type fun1_1 = function <A1,R1>                   (A1)          : R1
  type fun1_2 = function <A1,R1,R2>                (A1)          : R1,R2
  type fun1_3 = function <A1,R1,R2,R3>             (A1)          : R1,R2,R3
  type fun1_4 = function <A1,R1,R2,R3,R4>          (A1)          : R1,R2,R3,R4
  type fun2   = function <A1,A2>                   (A1,A2)
  type fun2_1 = function <A1,A2,R1>                (A1,A2)       : R1
  type fun2_2 = function <A1,A2,R1,R2>             (A1,A2)       : R1,R2
  type fun2_3 = function <A1,A2,R1,R2,R3>          (A1,A2)       : R1,R2,R3
  type fun2_4 = function <A1,A2,R1,R2,R3,R4>       (A1,A2)       : R1,R2,R3,R4
  type fun3   = function <A1,A2,A3>                (A1,A2,A3)
  type fun3_1 = function <A1,A2,A3,R1>             (A1,A2,A3)    : R1
  type fun3_2 = function <A1,A2,A3,R1,R2>          (A1,A2,A3)    : R1,R2
  type fun3_3 = function <A1,A2,A3,R1,R2,R3>       (A1,A2,A3)    : R1,R2,R3
  type fun3_4 = function <A1,A2,A3,R1,R2,R3,R4>    (A1,A2,A3)    : R1,R2,R3,R4
  type fun4   = function <A1,A2,A3,A4>             (A1,A2,A3,A4)
  type fun4_1 = function <A1,A2,A3,A4,R1>          (A1,A2,A3,A4) : R1
  type fun4_2 = function <A1,A2,A3,A4,R1,R2>       (A1,A2,A3,A4) : R1,R2
  type fun4_3 = function <A1,A2,A3,A4,R1,R2,R3>    (A1,A2,A3,A4) : R1,R2,R3
  type fun4_4 = function <A1,A2,A3,A4,R1,R2,R3,R4> (A1,A2,A3,A4) : R1,R2,R3,R4

  type fun5_0 = function <A1,A2,A3,A4,A5>             (A1,A2,A3,A4,A5)
  type fun5_1 = function <A1,A2,A3,A4,A5,R1>          (A1,A2,A3,A4,A5) : R1
  type fun5_4 = function <A1,A2,A3,A4,A5,R1,R2,R3,R4> (A1,A2,A3,A4,A5) : R1,R2,R3,R4

  void: function<R1,R2,R3>                  (fun0_3 <R1,R2,R3>                  ): fun0_3 <R1,R2,R3>
  void: function<R1,R2>                     (fun0_2 <R1,R2>                     ): fun0_2 <R1,R2>
  void: function<R1>                        (fun0_1 <R1>                        ): fun0_1 <R1>
  void: function                            (fun0                               ): fun0
  void: function<A1,R1,R2,R3,R4>            (fun1_4 <A1,R1,R2,R3,R4>            ): fun1_4 <A1,R1,R2,R3,R4>
  void: function<A1,R1,R2,R3>               (fun1_3 <A1,R1,R2,R3>               ): fun1_3 <A1,R1,R2,R3>
  void: function<A1,R1,R2>                  (fun1_2 <A1,R1,R2>                  ): fun1_2 <A1,R1,R2>
  void: function<A1,R1>                     (fun1_1 <A1,R1>                     ): fun1_1 <A1,R1>
  void: function<A1>                        (fun1   <A1>                        ): fun1   <A1>
  void: function<A1,A2,R1,R2,R3,R4>         (fun2_4 <A1,A2,R1,R2,R3,R4>         ): fun2_4 <A1,A2,R1,R2,R3,R4>
  void: function<A1,A2,R1,R2,R3>            (fun2_3 <A1,A2,R1,R2,R3>            ): fun2_3 <A1,A2,R1,R2,R3>
  void: function<A1,A2,R1,R2>               (fun2_2 <A1,A2,R1,R2>               ): fun2_2 <A1,A2,R1,R2>
  void: function<A1,A2,R1>                  (fun2_1 <A1,A2,R1>                  ): fun2_1 <A1,A2,R1>
  void: function<A1,A2>                     (fun2   <A1,A2>                     ): fun2   <A1,A2>
  void: function<A1,A2,A3,R1,R2,R3,R4>      (fun3_4 <A1,A2,A3,R1,R2,R3,R4>      ): fun3_4 <A1,A2,A3,R1,R2,R3,R4>
  void: function<A1,A2,A3,R1,R2,R3>         (fun3_3 <A1,A2,A3,R1,R2,R3>         ): fun3_3 <A1,A2,A3,R1,R2,R3>
  void: function<A1,A2,A3,R1,R2>            (fun3_2 <A1,A2,A3,R1,R2>            ): fun3_2 <A1,A2,A3,R1,R2>
  void: function<A1,A2,A3,R1>               (fun3_1 <A1,A2,A3,R1>               ): fun3_1 <A1,A2,A3,R1>
  void: function<A1,A2,A3>                  (fun3   <A1,A2,A3>                  ): fun3   <A1,A2,A3>
  void: function<A1,A2,A3,A4,R1,R2,R3,R4>   (fun4_4 <A1,A2,A3,A4,R1,R2,R3,R4>   ): fun4_4 <A1,A2,A3,A4,R1,R2,R3,R4>
  void: function<A1,A2,A3,A4,R1,R2,R3>      (fun4_3 <A1,A2,A3,A4,R1,R2,R3>      ): fun4_3 <A1,A2,A3,A4,R1,R2,R3>
  void: function<A1,A2,A3,A4,R1,R2>         (fun4_2 <A1,A2,A3,A4,R1,R2>         ): fun4_2 <A1,A2,A3,A4,R1,R2>
  void: function<A1,A2,A3,A4,R1>            (fun4_1 <A1,A2,A3,A4,R1>            ): fun4_1 <A1,A2,A3,A4,R1>
  void: function<A1,A2,A3,A4>               (fun4   <A1,A2,A3,A4>               ): fun4   <A1,A2,A3,A4>
  void: function<A1,A2,A3,A4,A5,R1,R2,R3,R4>(fun5_4 <A1,A2,A3,A4,A5,R1,R2,R3,R4>): fun5_4 <A1,A2,A3,A4,A5,R1,R2,R3,R4>
  void: function<A1,A2,A3,A4,A5,R1>         (fun5_1 <A1,A2,A3,A4,A5,R1>         ): fun5_1 <A1,A2,A3,A4,A5,R1>
  void: function<A1,A2,A3,A4,A5>            (fun5_0 <A1,A2,A3,A4,A5>            ): fun5_0 <A1,A2,A3,A4,A5>

  wrap: function                            (function(               function())           , integer): fun0
  wrap: function<R1>                        (function(               function(R1))         , integer): fun0_1 <R1>
  wrap: function<R1,R2>                     (function(               function(R1,R2))      , integer): fun0_2 <R1,R2>
  wrap: function<R1,R2,R3>                  (function(               function(R1,R2,R3))   , integer): fun0_3 <R1,R2,R3>
  wrap: function<R1,R2,R3,R4>               (function(               function(R1,R2,R3,R4)), integer): fun0_4 <R1,R2,R3,R4>
  wrap: function<A1>                        (function(A1,            function())           , integer): fun1   <A1>
  wrap: function<A1,R1>                     (function(A1,            function(R1))         , integer): fun1_1 <A1,R1>
  wrap: function<A1,R1,R2>                  (function(A1,            function(R1,R2))      , integer): fun1_2 <A1,R1,R2>
  wrap: function<A1,R1,R2,R3>               (function(A1,            function(R1,R2,R3))   , integer): fun1_3 <A1,R1,R2,R3>
  wrap: function<A1,R1,R2,R3,R4>            (function(A1,            function(R1,R2,R3,R4)), integer): fun1_4 <A1,R1,R2,R3,R4>
  wrap: function<A1,A2>                     (function(A1,A2,         function())           , integer): fun2   <A1,A2>
  wrap: function<A1,A2,R1>                  (function(A1,A2,         function(R1))         , integer): fun2_1 <A1,A2,R1>
  wrap: function<A1,A2,R1,R2>               (function(A1,A2,         function(R1,R2))      , integer): fun2_2 <A1,A2,R1,R2>
  wrap: function<A1,A2,R1,R2,R3>            (function(A1,A2,         function(R1,R2,R3))   , integer): fun2_3 <A1,A2,R1,R2,R3>
  wrap: function<A1,A2,R1,R2,R3,R4>         (function(A1,A2,         function(R1,R2,R3,R4)), integer): fun2_4 <A1,A2,R1,R2,R3,R4>
  wrap: function<A1,A2,A3>                  (function(A1,A2,A3,      function())           , integer): fun3   <A1,A2,A3>
  wrap: function<A1,A2,A3,R1>               (function(A1,A2,A3,      function(R1))         , integer): fun3_1 <A1,A2,A3,R1>
  wrap: function<A1,A2,A3,R1,R2>            (function(A1,A2,A3,      function(R1,R2))      , integer): fun3_2 <A1,A2,A3,R1,R2>
  wrap: function<A1,A2,A3,R1,R2,R3>         (function(A1,A2,A3,      function(R1,R2,R3))   , integer): fun3_3 <A1,A2,A3,R1,R2,R3>
  wrap: function<A1,A2,A3,R1,R2,R3,R4>      (function(A1,A2,A3,      function(R1,R2,R3,R4)), integer): fun3_4 <A1,A2,A3,R1,R2,R3,R4>
  wrap: function<A1,A2,A3,A4>               (function(A1,A2,A3,A4,   function())           , integer): fun4   <A1,A2,A3,A4>
  wrap: function<A1,A2,A3,A4,R1>            (function(A1,A2,A3,A4,   function(R1))         , integer): fun4_1 <A1,A2,A3,A4,R1>
  wrap: function<A1,A2,A3,A4,R1,R2>         (function(A1,A2,A3,A4,   function(R1,R2))      , integer): fun4_2 <A1,A2,A3,A4,R1,R2>
  wrap: function<A1,A2,A3,A4,R1,R2,R3>      (function(A1,A2,A3,A4,   function(R1,R2,R3))   , integer): fun4_3 <A1,A2,A3,A4,R1,R2,R3>
  wrap: function<A1,A2,A3,A4,A5,R1>         (function(A1,A2,A3,A4,A5,function(R1))         , integer): fun5_1 <A1,A2,A3,A4,A5,R1>
  wrap: function<A1,A2,A3,A4,A5,R1,R2,R3,R4>(function(A1,A2,A3,A4,A5,function(R1,R2,R3,R4)), integer): fun5_4 <A1,A2,A3,A4,A5,R1,R2,R3,R4>

  void: function(function): function
  run: function(function, function)
end

return Async
