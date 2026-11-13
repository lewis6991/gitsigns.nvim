-- libuv fs_event wrapper that filters events caused by file reads.

local uv = vim.uv

--- @class Gitsigns.FsEvent
--- @field private handle uv.uv_fs_event_t
local M = {}
M.__index = M

--- @alias Gitsigns.FsEvent.Callback fun(
---   err: string?,
---   filename: string?,
---   events: { change?: boolean, rename?: boolean }?,
---   stat: uv.fs_stat.result?
--- )

--- @param stat? uv.fs_stat.result
--- @return string|false
local function fingerprint(stat)
  if not stat then
    return false
  end
  return table.concat({
    stat.type,
    stat.dev,
    stat.ino,
    stat.size,
    stat.mtime.sec,
    stat.mtime.nsec,
    stat.ctime.sec,
    stat.ctime.nsec,
  }, ':')
end

--- @return Gitsigns.FsEvent?, string?, string?
function M.new()
  local handle, err, err_name = uv.new_fs_event()
  if not handle then
    return nil, err, err_name
  end
  return setmetatable({ handle = handle }, M)
end

--- Start a native watcher, filtering access-time-only events.
--- @param path string
--- @param flags {watch_entry?: boolean, stat?: boolean, recursive?: boolean}
--- @param callback Gitsigns.FsEvent.Callback Receives the changed entry's stat when available.
--- @param stat? uv.fs_stat.result Initial stat for path; obtained when omitted.
--- @return integer?, string?, string?
function M:start(path, flags, callback, stat)
  local handle = self.handle

  -- Compare metadata other than atime to filter events caused by reads.
  stat = stat or uv.fs_stat(path)
  local is_dir = stat and stat.type == 'directory'
  local previous = { [path] = fingerprint(stat) } --- @type table<string, string|false>

  return handle:start(path, flags, function(err, filename, events)
    -- An unknown directory entry may contain a real change. Preserve errors
    -- too, so callers can restart the watcher or select another backend.
    if err or (is_dir and not filename) then
      callback(err, filename, events)
      return
    end

    local target = is_dir and vim.fs.joinpath(path, filename) or path
    local current_stat = uv.fs_stat(target)
    local current = fingerprint(current_stat)
    local old = previous[target]
    -- Learn directory entries on their first event instead of scanning the
    -- directory at startup. The first event is passed through conservatively.
    previous[target] = current or nil
    if current ~= old then
      callback(nil, filename, events, current_stat)
    end
  end)
end

--- @return integer?, string?, string?
function M:stop()
  return self.handle:stop()
end

function M:close()
  self.handle:close()
end

--- @return boolean?, string?, string?
function M:is_closing()
  return self.handle:is_closing()
end

--- @return string?, string?, string?
function M:getpath()
  return self.handle:getpath()
end

return M
