local debounce_trailing = require('gitsigns.debounce').debounce_trailing
local util = require('gitsigns.util')
local log = require('gitsigns.debug.log')
local config = require('gitsigns.config').config
local Path = util.Path
local uv = vim.uv or vim.loop ---@diagnostic disable-line: deprecated

local FS_EVENT = 'fs_event'
local FS_POLL = 'fs_poll'
local FS_POLL_INTERVAL = 200

--- @param handle uv.uv_fs_event_t|uv.uv_fs_poll_t
local function close_handle(handle)
  if handle:is_closing() then
    return
  end

  handle:stop()
  handle:close()
end

--- Polling tracks logical git metadata targets. The actual poll handle may
--- point at the target itself or at its parent dir when the file is absent.
--- @param path string
--- @return string?
local function poll_fingerprint(path)
  local stat = uv.fs_stat(path)
  if not stat then
    return nil
  end

  local mtime = stat.mtime or {}
  local ctime = stat.ctime or {}

  return table.concat({
    tostring(stat.type or ''),
    tostring(stat.size or -1),
    tostring(mtime.sec or -1),
    tostring(mtime.nsec or -1),
    tostring(ctime.sec or -1),
    tostring(ctime.nsec or -1),
  }, ':')
end

--- Convert a logical target into the concrete path the backend should watch.
--- `fs_event` watches directories, while `fs_poll` prefers the file itself and
--- falls back to the parent dir until the file exists.
--- @param target string
--- @param is_fs_event boolean
--- @return string?
local function resolve_handle_path(target, is_fs_event)
  if is_fs_event then
    return Path.is_dir(target) and target or nil
  end

  if Path.exists(target) then
    return target
  end

  local parent = vim.fs.dirname(target)
  if parent and parent ~= target and Path.is_dir(parent) then
    return parent
  end
end

--- @param filename string?
--- @param events { change:boolean?, rename:boolean? }?
--- @return boolean notify
local function should_notify_fs_event(filename, events)
  -- The luv docs say filename is passed as a string but it has been observed
  -- to sometimes be nil.
  --    https://github.com/lewis6991/gitsigns.nvim/issues/848
  if not filename then
    log.eprint('No filename')
    return true
  end

  local details = vim.inspect(events, { indent = '', newline = ' ' })
  if vim.startswith(filename, '.watchman-cookie') or vim.startswith(filename, 'index.lock') then
    log.dprintf("Git dir update: '%s' %s (ignoring)", filename, details)
    return false
  end

  log.dprintf("Git dir update: '%s' %s", filename, details)
  return true
end

--- Poll callbacks only tell us that a watched handle path changed. Compare
--- logical target fingerprints so we only notify on relevant gitdir changes.
--- @param handle_path string
--- @param target_fingerprints table<string, string?>
--- @return boolean notify
local function should_notify_fs_poll(handle_path, target_fingerprints)
  for target, previous in pairs(target_fingerprints) do
    if previous ~= poll_fingerprint(target) then
      log.dprintf("Git dir update: '%s' { poll = true }", handle_path)
      return true
    end
  end

  return false
end

--- @class Gitsigns.Repo.Watcher
--- @field private update_callbacks fun()[]
--- @field private notify_debounced fun()
--- @field private gitdir string
--- @field private commondir string
--- @field private handles table<string, uv.uv_fs_event_t|uv.uv_fs_poll_t> Map from concrete handle path -> handle
--- @field private head_ref? string
--- @field private _backend 'fs_event'|'fs_poll'
--- @field private _target_fingerprints table<string, string?> Snapshot of fs_poll logical targets
--- @field private _closed? true
--- @field private _gc userdata? Used for garbage collection
local Watcher = {}
Watcher.__index = Watcher

--- @param gitdir string
--- @param commondir? string
--- @return Gitsigns.Repo.Watcher
function Watcher.new(gitdir, commondir)
  local self = setmetatable({}, Watcher)

  self.update_callbacks = {}
  self.gitdir = gitdir
  self.commondir = commondir or gitdir
  self.handles = {}
  self._backend = FS_EVENT
  self._target_fingerprints = {}
  local weak_self = util.weak_ref(self)
  self.notify_debounced = debounce_trailing(200, function()
    local watcher = weak_self.ref
    if watcher then
      watcher:_notify_callbacks()
    end
  end)

  local handles = self.handles
  self._gc = util.gc_proxy(function()
    for _, handle in pairs(handles) do
      close_handle(handle)
    end
  end)

  self:_sync_watches()

  return self
end

function Watcher:close()
  if self._closed then
    return
  end

  self._closed = true
  self.update_callbacks = {}
  self:_clear_handle_paths()
end

--- @private
--- @param handle_path string
function Watcher:_drop_handle_path(handle_path)
  local handle = self.handles[handle_path]
  if not handle then
    return
  end

  close_handle(handle)
  self.handles[handle_path] = nil
end

--- @private
function Watcher:_clear_handle_paths()
  for handle_path in pairs(self.handles) do
    self:_drop_handle_path(handle_path)
  end
end

--- @private
--- @param handle_path string
--- @param err string
--- @return false
function Watcher:_handle_fs_poll_error(handle_path, err)
  log.dprintf('Git dir update error: %s', err)
  self:_drop_handle_path(handle_path)
  self:_sync_watches()
  return false
end

--- @private
--- @param err string
--- @return false
function Watcher:_fallback_to_fs_poll(err)
  log.dprintf('Git dir update error: %s', err)
  if not config._allow_fs_poll_fallback then
    local msg = ('Git dir watcher backend failed (%s), fs_poll fallback is disabled'):format(err)
    log.eprint(msg)
    if config._test_mode then
      error(msg, 0)
    end
    return false
  end

  log.dprintf('Git dir watcher backend failed (%s), falling back to %s', err, FS_POLL)

  self._backend = FS_POLL
  self._target_fingerprints = {}
  self:_clear_handle_paths()
  self:_sync_watches()

  log.dprint(('Git dir update: <%s fallback>'):format(FS_POLL))
  self.notify_debounced()
  return false
end

--- @private
--- @param handle_path string
--- @return boolean
function Watcher:_start_handle_path(handle_path)
  local backend = self._backend
  local is_fs_event = backend == FS_EVENT
  local handle, err, err_name = (is_fs_event and uv.new_fs_event or uv.new_fs_poll)()
  err = err_name or err
  if not handle then
    err = err or ('uv.new_' .. backend .. ' failed')
    if not is_fs_event then
      error(err)
    end
    return self:_fallback_to_fs_poll(err)
  end

  self.handles[handle_path] = handle

  local weak_self = util.weak_ref(self)
  local callback = function(err0, arg1, arg2)
    local watcher = weak_self.ref
    if not watcher then
      log.dprint('watcher was garbage collected')
      return
    end

    if watcher._closed then
      log.dprint('watcher was closed')
      return
    end

    if watcher.handles[handle_path] ~= handle then
      return
    end

    if err0 then
      if is_fs_event then
        watcher:_fallback_to_fs_poll(err0)
      else
        watcher:_handle_fs_poll_error(handle_path, err0)
      end
      return
    end

    local should_notify
    if is_fs_event then
      should_notify = should_notify_fs_event(arg1, arg2)
    else
      should_notify = should_notify_fs_poll(handle_path, watcher._target_fingerprints)
      -- A poll callback may mean the target appeared or disappeared, so the
      -- next watch should move between the file and its parent dir.
      watcher:_sync_watches()
    end

    if should_notify then
      watcher.notify_debounced()
    end
  end

  log.dprintf('Starting %s on %s', backend, handle_path)
  local start_arg = is_fs_event and {} or FS_POLL_INTERVAL
  --- @diagnostic disable-next-line: param-type-mismatch
  local ok, start_err, start_err_name = handle:start(handle_path, start_arg, callback)

  if ok ~= nil then
    return true
  end

  self:_drop_handle_path(handle_path)
  err = start_err_name or start_err or 'watcher start failed'
  if not is_fs_event then
    error(err)
  end
  return self:_fallback_to_fs_poll(err)
end

--- @private
--- Reconcile the concrete handle paths with the logical targets we care about.
--- In poll mode this also snapshots the targets so callbacks can ignore
--- unrelated parent-dir changes and only notify on git metadata updates.
function Watcher:_sync_watches()
  if self._closed then
    return
  end

  local is_fs_event = self._backend == FS_EVENT
  local logical_targets = is_fs_event and self:_fs_event_targets() or self:_fs_poll_targets()

  local desired_handle_paths = {} --- @type table<string, true>
  local target_fingerprints = not is_fs_event and {} or nil --- @type table<string, string?>?

  for _, target in ipairs(logical_targets) do
    if target_fingerprints then
      -- Fingerprints belong to logical targets, not handle paths. A missing
      -- file may be polled via its parent dir until it appears.
      target_fingerprints[target] = poll_fingerprint(target)
    end

    local handle_path = resolve_handle_path(target, is_fs_event)
    if handle_path then
      desired_handle_paths[handle_path] = true
    end
  end

  for handle_path in pairs(self.handles) do
    if not desired_handle_paths[handle_path] then
      self:_drop_handle_path(handle_path)
    end
  end

  for handle_path in pairs(desired_handle_paths) do
    if not self.handles[handle_path] then
      if not self:_start_handle_path(handle_path) then
        return
      end
    end
  end

  if target_fingerprints then
    self._target_fingerprints = target_fingerprints
  end
end

--- @private
--- @return string[]
function Watcher:_fs_event_targets()
  local targets = {
    self.gitdir,
    Path.join(self.commondir, 'reftable'),
  }

  if self.commondir ~= self.gitdir then
    targets[#targets + 1] = self.commondir
  end

  if self.head_ref then
    local rel_dir = vim.fs.dirname(self.head_ref)
    if rel_dir and rel_dir ~= '.' then
      targets[#targets + 1] = Path.join(self.commondir, rel_dir)
    end
  end

  return targets
end

--- @private
--- @return string[]
function Watcher:_fs_poll_targets()
  local targets = {
    Path.join(self.gitdir, 'HEAD'),
    Path.join(self.gitdir, 'index'),
    Path.join(self.commondir, 'packed-refs'),
    Path.join(self.commondir, 'reftable'),
  }

  if self.head_ref then
    targets[#targets + 1] = Path.join(self.commondir, self.head_ref)
  end

  return targets
end

--- @param head_ref? string
function Watcher:set_head_ref(head_ref)
  if self.head_ref == head_ref then
    return
  end

  self.head_ref = head_ref
  self:_sync_watches()
end

--- @param callback fun() Callback function to be invoked on update.
--- @return fun() deregister Function to remove the callback from the watcher.
function Watcher:on_update(callback)
  -- Make sure insertion order is preserved as pos 1 is used by the repo object
  -- and must run before the buffer callbacks.
  table.insert(self.update_callbacks, callback)
  return function()
    for i, cb in ipairs(self.update_callbacks) do
      if cb == callback then
        table.remove(self.update_callbacks, i)
        break
      end
    end
  end
end

--- @private
function Watcher:_notify_callbacks()
  if self._closed then
    return
  end

  vim.schedule(function()
    for _, cb in ipairs(self.update_callbacks) do
      local ok, err = pcall(cb)
      if not ok then
        log.eprintf('Repo watcher callback error: %s', err)
      end
    end
  end)
end

return Watcher
