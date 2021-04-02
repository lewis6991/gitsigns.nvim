local record Async
  type future = function(function)

  await: function(future)
  scheduler: future
  execute: function
  void: function(function): function
  run: function
  wrap: function(function,integer): function
  async: function(function): function
end

return Async
