local debounce_trailing = require('gitsigns.debounce').debounce_trailing
local util = require('gitsigns.util')
local log = require('gitsigns.debug.log')
local Path = util.Path

--- vim.inspect but on one line
--- @param x any
--- @return string
local function inspect(x)
  return vim.inspect(x, { indent = '', newline = ' ' })
end

--- @class Gitsigns.Repo.Watcher
--- @field private update_callbacks fun()[]
--- @field private notify_callbacks_debounced fun(weak_self:{ref:Gitsigns.Repo.Watcher})
--- @field private gitdir string
--- @field private commondir string
--- @field private handles table<string, uv.uv_fs_event_t> Map from watched dir -> handle
--- @field private head_ref_dir? string
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
  self.notify_callbacks_debounced = debounce_trailing(200, Watcher.notify_callbacks)

  local weak_self = util.weak_ref(self)

  self._gc = util.gc_proxy(function()
    for _, handle in pairs(self.handles) do
      handle:stop()
      handle:close()
    end
  end)

  -- Changes to nested refs (e.g. `refs/heads/main`) may not be reported when
  -- only watching the gitdir root, so we add extra watches as needed.
  self:_watch_dir(gitdir, weak_self)

  if self.commondir ~= gitdir then
    self:_watch_dir(self.commondir, weak_self)
  end

  local reftable_dir = Path.join(self.commondir, 'reftable')
  self:_watch_dir(reftable_dir, weak_self)

  return self
end

--- @private
--- @param dir string
--- @param weak_self {ref:Gitsigns.Repo.Watcher}
function Watcher:_watch_dir(dir, weak_self)
  if self.handles[dir] or not Path.is_dir(dir) then
    return
  end

  local handle = assert(vim.uv.new_fs_event())
  self.handles[dir] = handle

  log.dprintf('Starting git dir watcher on %s', dir)
  handle:start(dir, {}, Watcher.handler(weak_self))
end

--- @private
--- @param dir string
function Watcher:_unwatch_dir(dir)
  local handle = self.handles[dir]
  if not handle then
    return
  end

  handle:stop()
  handle:close()
  self.handles[dir] = nil
end

--- Watch the directory containing `head_ref` under commondir.
--- This ensures we see branch-tip moves which update the target ref file but
--- don't necessarily touch `gitdir/HEAD`.
--- @param head_ref? string
function Watcher:set_head_ref(head_ref)
  local old_dir = self.head_ref_dir
  local new_dir --- @type string?

  if head_ref then
    local rel_dir = vim.fs.dirname(head_ref)
    if rel_dir and rel_dir ~= '.' then
      new_dir = Path.join(self.commondir, rel_dir)
    end
  end

  if old_dir and old_dir ~= new_dir then
    self:_unwatch_dir(old_dir)
    self.head_ref_dir = nil
  end

  if new_dir and not self.head_ref_dir then
    self.head_ref_dir = new_dir
    self:_watch_dir(new_dir, util.weak_ref(self))
  end
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

--- @param weak_self {ref:Gitsigns.Repo.Watcher}
function Watcher.notify_callbacks(weak_self)
  local self = weak_self.ref
  if not self then
    return -- garbage collected
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

--- @param weak_self {ref:Gitsigns.Repo.Watcher}
--- @return fun(err:string?, filename:string, events:{ change:boolean?, rename:boolean? })
function Watcher.handler(weak_self)
  --- @param err string?
  --- @param filename string
  --- @param events { change: boolean?, rename: boolean? }
  return function(err, filename, events)
    local __FUNC__ = 'watcher.handler1'

    local self = weak_self.ref
    if not self then
      log.dprint('watcher was garbage collected')
      return
    end

    if err then
      log.dprintf('Git dir update error: %s', err)
      return
    end

    -- The luv docs say filename is passed as a string but it has been observed
    -- to sometimes be nil.
    --    https://github.com/lewis6991/gitsigns.nvim/issues/848
    if not filename then
      log.eprint('No filename')
    else
      for _, ex in ipairs({
        '.watchman-cookie',
        'index.lock',
      }) do
        if vim.startswith(filename, ex) then
          log.dprintf("Git dir update: '%s' %s (ignoring)", filename, inspect(events))
          return
        end
      end

      log.dprintf("Git dir update: '%s' %s", filename, inspect(events))
    end

    self.notify_callbacks_debounced(weak_self)
  end
end

return Watcher
