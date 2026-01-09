local debounce_trailing = require('gitsigns.debounce').debounce_trailing
local util = require('gitsigns.util')
local log = require('gitsigns.debug.log')

--- vim.inspect but on one line
--- @param x any
--- @return string
local function inspect(x)
  return vim.inspect(x, { indent = '', newline = ' ' })
end

--- @class Gitsigns.Repo.Watcher
--- @field private update_callbacks table<fun(),true>
--- @field private head_update_callbacks table<fun(),true>
--- @field private handle uv.uv_fs_event_t
--- @field private handler_debounced fun(weak_self:{ref:Gitsigns.Repo.Watcher})
--- @field private changed_files table<string,true>
--- @field private gitdir string
--- @field private weak_repo {ref:Gitsigns.Repo} Weak reference to repo
--- @field private _gc userdata? Used for garbage collection
local Watcher = {}
Watcher.__index = Watcher

--- @param gitdir string
--- @return Gitsigns.Repo.Watcher
function Watcher.new(gitdir)
  local handle = assert(vim.uv.new_fs_event())

  --- @type Gitsigns.Repo.Watcher
  local self = setmetatable({}, Watcher)

  self.update_callbacks = {}
  self.head_update_callbacks = {}
  self.changed_files = {}
  self.handle = handle
  self.handler_debounced = debounce_trailing(200, function(weak_self)
    vim.schedule(function()
      Watcher.handler2(weak_self)
    end)
  end)

  self._gc = util.gc_proxy(function()
    handle:stop()
    handle:close()
  end)

  log.dprintf('Starting git dir watcher on %s', gitdir)
  self.handle:start(gitdir, {}, Watcher.handler1(util.weak_ref(self)))

  return self
end

--- @param callback fun() Callback function to be invoked on update.
function Watcher:on_head_update(callback)
  self.head_update_callbacks[callback] = true
end

--- @param callback fun() Callback function to be invoked on update.
--- @return fun() deregister Function to remove the callback from the watcher.
function Watcher:on_update(callback)
  self.update_callbacks[callback] = true
  return function()
    self.update_callbacks[callback] = nil
  end
end

--- @private
--- @param weak_self {ref:Gitsigns.Repo.Watcher}
function Watcher.handler2(weak_self)
  local self = weak_self.ref
  if not self then
    return -- garbage collected
  end

  local head_changed = self.changed_files.HEAD or false

  self.changed_files = {}

  if head_changed then
    for cb in pairs(self.head_update_callbacks) do
      cb()
    end
  end

  for cb in pairs(self.update_callbacks) do
    vim.schedule(cb)
  end
end

function Watcher.handler1(weak_self)
  --- @param err string?
  --- @param filename string
  --- @param events { change: boolean?, rename: boolean? }
  return function(err, filename, events)
    local __FUNC__ = 'watcher.handler1'

    local watcher = weak_self.ref
    if not watcher then
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
      return
    end

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

    watcher.changed_files[filename] = true

    watcher.handler_debounced(weak_self)
  end
end

return Watcher
