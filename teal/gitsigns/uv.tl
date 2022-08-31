local nvim = require('gitsigns.nvim')

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

nvim.autocmd('VimLeavePre', {
  callback = function()
    for _, e in pairs(handles) do
      local handle = e[1]
      if handle and not handle:is_closing() then
        handle:close()
      end
    end
  end
})

function M.new_timer(longlived: boolean): uv.Timer | string
  local r = uv.new_timer()
  if r is uv.Timer then
    handles[#handles+1] = {r as uv.Handle, longlived, debug.traceback()}
  end
  return r
end

function M.new_fs_poll(longlived: boolean): uv.FSPollObj | string
  local r = uv.new_fs_poll()
  if r is uv.FSPollObj then
    handles[#handles+1] = {r as uv.Handle, longlived, debug.traceback()}
  end
  return r
end

function M.new_pipe(ipc: boolean): uv.Pipe | string
  local r = uv.new_pipe(ipc)
  if r is uv.Pipe then
    handles[#handles+1] = {r as uv.Handle, false, debug.traceback()}
  end
  return r
end

function M.spawn(cmd: string, opts: uv.SpawnOpts, on_exit: function(integer, integer)): uv.Process, integer
  local handle, pid = uv.spawn(cmd, opts, on_exit)
  if handle then
    handles[#handles+1] = {handle as uv.Handle, false, cmd..' '..vim.inspect(opts)}
  end
  return handle, pid
end

return M
