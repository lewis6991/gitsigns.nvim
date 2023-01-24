local uv = vim.loop

local record M
  handles: {integer:{uv.Handle, boolean, string}}
end

local handles: {integer:{uv.Handle, boolean, string}}= {}

M.handles = handles

function M.print_handles()
  local none = true
  for _, e in pairs(handles) do
    local handle, longlived, tr = unpack(e) as (uv.Handle, boolean, string)
    if handle and not longlived and not handle:is_closing() then
      print('')
      print(tr)
      none = false
    end
  end
  if none then
    print('No active handles')
  end
end

vim.api.nvim_create_autocmd('VimLeavePre', {
  callback = function()
    for _, e in pairs(handles) do
      local handle = e[1]
      if handle and not handle:is_closing() then
        handle:close()
      end
    end
  end
})

function M.new_timer(longlived: boolean): uv.Timer
  local r = uv.new_timer()
  table.insert(handles, {r as uv.Handle, longlived, debug.traceback()})
  return r
end

function M.new_fs_poll(longlived: boolean): uv.FSPollObj
  local r = uv.new_fs_poll()
  table.insert(handles, {r as uv.Handle, longlived, debug.traceback()})
  return r
end

function M.new_pipe(ipc: boolean): uv.Pipe
  local r = uv.new_pipe(ipc)
  table.insert(handles, {r as uv.Handle, false, debug.traceback()})
  return r
end

function M.spawn(cmd: string, opts: uv.SpawnOpts, on_exit: function(integer, integer)): uv.Process, integer
  local handle, pid = uv.spawn(cmd, opts, on_exit)
  if handle then
    table.insert(handles, {handle as uv.Handle, false, cmd..' '..vim.inspect(opts)})
  end
  return handle, pid
end

return M
