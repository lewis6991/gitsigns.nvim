local uv = vim.loop

local record M
  handles: {integer:{uv.Handle, boolean, string}}
end

--- @type table<integer,{[1]: uv_handle_t, [2]: boolean, [3]: string}>
local handles: {integer:{uv.Handle, boolean, string}} = {}

M.handles = handles

function M.print_handles()
  local none = true
  for _, e in pairs(handles) do
    local handle, longlived, tr = e[1], e[2], e[3]
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

--- @param longlived boolean
--- @return uv_timer_t?
function M.new_timer(longlived: boolean): uv.Timer
  local r = uv.new_timer()
  if r then
    table.insert(handles, {r as uv.Handle, longlived, debug.traceback()})
  end
  return r
end

--- @param longlived boolean
--- @return uv_fs_poll_t?
function M.new_fs_poll(longlived: boolean): uv.FSPollObj
  local r = uv.new_fs_poll()
  if r then
    table.insert(handles, {r as uv.Handle, longlived, debug.traceback()})
  end
  return r
end

--- @param ipc boolean
--- @return uv_pipe_t?
function M.new_pipe(ipc: boolean): uv.Pipe
  local r = uv.new_pipe(ipc)
  if r then
    table.insert(handles, {r as uv.Handle, false, debug.traceback()})
  end
  return r
end

--- @param cmd string
--- @param opts uv.aliases.spawn_options
--- @param on_exit fun(_: integer, _, integer): uv_process_t, integer
--- @return uv_process_t?, string|integer
function M.spawn(cmd: string, opts: uv.SpawnOpts, on_exit: function(integer, integer)): uv.Process, integer
  local handle, pid = uv.spawn(cmd, opts, on_exit)
  if handle then
    table.insert(handles, {handle as uv.Handle, false, cmd..' '..vim.inspect(opts)})
  end
  return handle, pid
end

return M
