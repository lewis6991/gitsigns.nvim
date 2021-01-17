local record Job

  record JobSpec
    command: string
    args: {string}
    cwd: string
    on_stdout: function
    on_stderr: function
    on_exit: function
    writer: {string}
  end

  new: function(Job, JobSpec): Job
  start: function(Job)
end

return Job
