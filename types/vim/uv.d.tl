local record M
  cwd: function(): string
  record Timer
    userdata

    start: function(Timer, number, number, function): number
    stop: function(Timer): number
    close: function(Timer): number
    is_closing: function(Timer): boolean
    again: function(Timer): number
    set_repeat: function(Timer, number): number
    get_repeat: function(Timer): number
    get_due_in: function(Timer): number
  end
  hrtime: function(): number
  new_timer: function(): Timer
  timer_start: function(Timer, integer, integer, function()): integer | string

  new_fs_event: function()

  record FSPollObj
    userdata
    is_closing: function(FSPollObj): boolean | string
    close: function(FSPollObj)
    start: function(FSPollObj, string, integer, function)
    stop: function(FSPollObj)
    getpath: function(FSPollObj): string
  end
  new_fs_poll: function(): FSPollObj

  record FsStatRet
    dev : number
    mode : number
    nlink : number
    uid : number
    gid : number
    rdev : number
    ino : number
    size : number
    blksize : number
    blocks : number
    flags : number
    gen : number
    record Time
      sec : number
      nsec : number
    end
    atime: Time
    mtime: Time
    ctime: Time
    birthtime: Time
    type : string
  end

  fs_stat: function(string, function): FsStatRet

  fs_realpath: function(string): string

  new_tcp: function()

  sleep: function(integer)

  record Handle
    userdata

    close: function(Handle)
    is_closing: function(Handle): boolean | string
  end

  record Pipe
    userdata

    close: function(Pipe)
    is_closing: function(Pipe): boolean | string
    read_start: function(Pipe, err: any, data: string)
    read_stop: function(Pipe)
    write: function(Pipe, string, function())

    open: function(any)
  end

  record Process
    userdata

    close: function(Process)
  end

  record SpawnOpts
    stdio: {Pipe, Pipe, Pipe}
    args: {string}
    cwd: string
    env: {string}
  end

  spawn: function(string, SpawnOpts, function(integer, integer)): Process, integer

  read_start: function(Pipe, function)
  new_pipe: function(boolean): Pipe
  shutdown: function(any, function)
  close: function(any, function)

  record WorkCtx
    queue: function(WorkCtx, ...:any)
  end

  new_work: function(function, function): WorkCtx
end

return M
