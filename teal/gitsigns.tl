local async = require('gitsigns.async')
local void = require('gitsigns.async').void
local scheduler = require('gitsigns.async').scheduler

local Status     = require("gitsigns.status")
local git        = require('gitsigns.git')
local manager    = require('gitsigns.manager')
local nvim       = require('gitsigns.nvim')
local util       = require('gitsigns.util')
local hl         = require('gitsigns.highlight')

local gs_cache   = require('gitsigns.cache')
local cache      = gs_cache.cache
local CacheEntry = gs_cache.CacheEntry

local gs_config  = require('gitsigns.config')
local Config     = gs_config.Config
local config     = gs_config.config

local gs_debug   = require("gitsigns.debug")
local dprintf    = gs_debug.dprintf
local dprint     = gs_debug.dprint

local Debounce          = require("gitsigns.debounce")
local debounce_trailing = Debounce.debounce_trailing
local throttle_by_id    = Debounce.throttle_by_id

local api = vim.api
local uv = vim.loop
local current_buf = api.nvim_get_current_buf

local record M
  setup      : function(cfg: Config)
  detach     : function(bufnr: integer, _keep_signs: boolean)
  detach_all : function()
  attach     : function(cbuf: integer, trigger: string)

  -- Exposed for tests
  parse_fugitive_uri: function(name: string): string, string
end

--- Detach Gitsigns from all buffers it is attached to.
M.detach_all = function()
  for k, _ in pairs(cache as {integer:CacheEntry}) do
    M.detach(k)
  end
end

--- Detach Gitsigns from the buffer {bufnr}. If {bufnr} is not
--- provided then the current buffer is used.
---
--- Parameters: ~
---     {bufnr}  (number): Buffer number
M.detach = function(bufnr: integer, _keep_signs: boolean)
  -- When this is called interactively (with no arguments) we want to remove all
  -- the signs, however if called via a detach event (due to nvim_buf_attach)
  -- then we don't want to clear the signs in case the buffer is just being
  -- updated due to the file externally changing. When this happens a detach and
  -- attach event happen in sequence and so we keep the old signs to stop the
  -- sign column width moving about between updates.
  bufnr = bufnr or current_buf()
  dprint('Detached')
  local bcache = cache[bufnr]
  if not bcache then
    dprint('Cache was nil')
    return
  end

  manager.detach(bufnr, _keep_signs)

  -- Clear status variables
  Status:clear(bufnr)

  cache:destroy(bufnr)
end

local function parse_fugitive_uri(name: string): string, string
  local _, _, root_path, sub_module_path, commit, real_path =
    name:find([[^fugitive://(.*)/%.git(.*/)/(%x-)/(.*)]])
  if commit == '0' then
    -- '0' means the index so cleat commit so we attach normally
    commit = nil
  end
  if root_path then
    sub_module_path = sub_module_path:gsub("^/modules", "")
    name = root_path .. sub_module_path .. real_path
  end
  return name, commit
end

local function parse_gitsigns_uri(name: string): string, string
  -- TODO(lewis6991): Support submodules
  local _, _, root_path, commit, rel_path =
    name:find([[^gitsigns://(.*)/%.git/(.*):(.*)]])
  if commit == ':0' then
    -- ':0' means the index so clear commit so we attach normally
    commit = nil
  end
  if root_path then
    name = root_path .. '/' .. rel_path
  end
  return name, commit
end

local function get_buf_path(bufnr: integer): string, string
  local file =
    uv.fs_realpath(api.nvim_buf_get_name(bufnr))
      or
    api.nvim_buf_call(bufnr, function(): string
      return vim.fn.expand('%:p')
    end)

  if not vim.wo.diff then
    if vim.startswith(file, 'fugitive://') then
      local path, commit = parse_fugitive_uri(file)
      dprintf("Fugitive buffer for file '%s' from path '%s'", path, file)
      path = uv.fs_realpath(path)
      if path then
        return path, commit
      end
    end

    if vim.startswith(file, 'gitsigns://') then
      local path, commit = parse_gitsigns_uri(file)
      dprintf("Gitsigns buffer for file '%s' from path '%s'", path, file)
      path = uv.fs_realpath(path)
      if path then
        return path, commit
      end
    end
  end

  return file
end

local vimgrep_running = false

local function on_lines(_, bufnr: integer, _, first: integer, last_orig: integer, last_new: integer, byte_count: integer): boolean
  if first == last_orig and last_orig == last_new and byte_count == 0 then
    -- on_lines can be called twice for undo events; ignore the second
    -- call which indicates no changes.
    return
  end
  return manager.on_lines(bufnr, first, last_orig, last_new)
end

local function on_reload(_, bufnr: integer)
  local __FUNC__ = 'on_reload'
  dprint('Reload')
  manager.update_debounced(bufnr)
end

local function on_detach(_, bufnr: integer)
  M.detach(bufnr, true)
end

local function on_attach_pre(bufnr: integer): string, string
  local gitdir, toplevel: string, string
  if config._on_attach_pre then
    local res: any = async.wrap(config._on_attach_pre, 2)(bufnr)
    dprintf('ran on_attach_pre with result %s', vim.inspect(res))
    if res is table then
      if type(res.gitdir) == 'string' then
        gitdir = res.gitdir as string
      end
      if type(res.toplevel) == 'string' then
        toplevel = res.toplevel as string
      end
    end
  end
  return gitdir, toplevel
end

local function try_worktrees(_bufnr: integer, file: string, encoding: string): git.Obj
  if not config.worktrees then
    return
  end

  for _, wt in ipairs(config.worktrees) do
    local git_obj = git.Obj.new(file, encoding, wt.gitdir, wt.toplevel)
    if git_obj and git_obj.object_name then
      dprintf('Using worktree %s', vim.inspect(wt))
      return git_obj
    end
  end
end

-- Ensure attaches cannot be interleaved.
-- Since attaches are asynchronous we need to make sure an attach isn't
-- performed whilst another one is in progress.
local attach_throttled = throttle_by_id(function(cbuf: integer, aucmd: string)
  local __FUNC__ = 'attach'
  if vimgrep_running then
    dprint('attaching is disabled')
    return
  end

  if cache[cbuf] then
    dprint('Already attached')
    return
  end

  if aucmd then
    dprintf('Attaching (trigger=%s)', aucmd)
  else
    dprint('Attaching')
  end

  if not api.nvim_buf_is_loaded(cbuf) then
    dprint('Non-loaded buffer')
    return
  end

  if api.nvim_buf_line_count(cbuf) > config.max_file_length then
    dprint('Exceeds max_file_length')
    return
  end

  if api.nvim_buf_get_option(cbuf, 'buftype') ~= '' then
    dprint('Non-normal buffer')
    return
  end

  local file, commit = get_buf_path(cbuf)
  local encoding = vim.bo[cbuf].fileencoding

  local file_dir = util.dirname(file)

  if not file_dir or not util.path_exists(file_dir) then
    dprint('Not a path')
    return
  end

  local gitdir_oap, toplevel_oap = on_attach_pre(cbuf)
  local git_obj = git.Obj.new(file, encoding, gitdir_oap, toplevel_oap)

  if not git_obj then
    git_obj = try_worktrees(cbuf, file, encoding)
    scheduler()
  end

  if not git_obj then
    dprint('Empty git obj')
    return
  end
  local repo = git_obj.repo

  scheduler()
  Status:update(cbuf, {
    head   = repo.abbrev_head,
    root   = repo.toplevel,
    gitdir = repo.gitdir,
  })

  if vim.startswith(file, repo.gitdir..util.path_sep) then
    dprint('In non-standard git dir')
    return
  end

  if not util.path_exists(file) or uv.fs_stat(file).type == 'directory' then
    dprint('Not a file')
    return
  end

  if not git_obj.relpath then
    dprint('Cannot resolve file in repo')
    return
  end

  if not config.attach_to_untracked and git_obj.object_name == nil then
    dprint('File is untracked')
    return
  end

  -- On windows os.tmpname() crashes in callback threads so initialise this
  -- variable on the main thread.
  scheduler()

  if config.on_attach and config.on_attach(cbuf) == false then
    dprint('User on_attach() returned false')
    return
  end

  cache[cbuf] = CacheEntry.new {
    base           = config.base,
    file           = file,
    commit         = commit,
    gitdir_watcher = manager.watch_gitdir(cbuf, repo.gitdir),
    git_obj        = git_obj
  }

  -- Make sure to attach before the first update (which is async) so we pick up
  -- changes from BufReadCmd.
  api.nvim_buf_attach(cbuf, false, {
    on_lines  = on_lines,
    on_reload = on_reload,
    on_detach = on_detach
  })

  -- Initial update
  manager.update(cbuf, cache[cbuf])

  if config.keymaps and not vim.tbl_isempty(config.keymaps) then
    require('gitsigns.mappings')(config.keymaps as {string:any}, cbuf)
  end
end)

--- Attach Gitsigns to the buffer.
---
--- Attributes: ~
---     {async}
---
--- Parameters: ~
---     {bufnr}  (number): Buffer number
M.attach = void(function(bufnr: integer, _trigger: string)
  attach_throttled(bufnr or current_buf(), _trigger)
end)

local M0 = M as {string:function}

local function complete(arglead: string, line: string): {string}
  local n: integer = #vim.split(line, '%s+')

  local matches: {string} = {}
  if n == 2 then
    local actions = require('gitsigns.actions') as {string:function}
    for _, m in ipairs{actions, M0} do
      for func, _ in pairs(m) do
        if vim.startswith(func, '_') then
          -- exclude
        elseif vim.startswith(func, arglead) then
          table.insert(matches, func)
        end
      end
    end
  end
  return matches
end

-- try to parse each argument as a lua boolean, nil or number, if fails then
-- keep argument as a string:
--
--   'false'    -> false
--   'nil'      -> nil
--   '100'      -> 100
--   'HEAD~300' -> 'HEAD~300'
local function parse_to_lua(a: string): any
  if tonumber(a) then
    return tonumber(a)
  elseif a == 'false' or a == 'true' then
    return a == 'true'
  elseif a == 'nil' then
    return nil
  end
  return a
end

local run_cmd_func = void(function(params: api.UserCmdParams)
  local pos_args_raw, named_args_raw = require('gitsigns.argparse').parse_args(params.args)

  local func = pos_args_raw[1]

  if not func then
    func = async.wrap(vim.ui.select, 3)(complete('', 'Gitsigns '), {})
  end

  local pos_args = vim.tbl_map(parse_to_lua, vim.list_slice(pos_args_raw, 2)) as {any}
  local named_args = vim.tbl_map(parse_to_lua, named_args_raw) as {string:any}

  local actions = require('gitsigns.actions')
  local actions0 = actions as {string:function}

  local cmd_func = actions.get_cmd_func(func)
  if cmd_func then
    -- Action has a specialised mapping function from command form to lua
    -- function
    cmd_func(pos_args, named_args, params)
    return
  end

  if type(actions0[func]) == 'function' then
    actions0[func](unpack(pos_args), named_args)
    return
  end

  if type(M0[func]) == 'function' then
    -- Note functions here do not have named arguments
    M0[func](unpack(pos_args))
    return
  end

  error(string.format('%s is not a valid function or action', func))
end)

local function setup_command()
  nvim.command('Gitsigns', run_cmd_func,
  { force = true, nargs = '*', range = true, complete = complete })
end

local function wrap_func(fn: function, ...: any): function()
  local args = {...}
  local nargs = select('#', ...)
  return function()
    fn(unpack(args, 1, nargs))
  end
end

local function autocmd(event: string, opts: function|vim.api.AutoCmdOpts)
  local opts0: vim.api.AutoCmdOpts = {}
  if opts is function then
    opts0.callback = wrap_func(opts)
  else
    opts0 = opts
  end
  opts0.group = 'gitsigns'
  nvim.autocmd(event, opts0)
end

local function on_or_after_vimenter(fn: function)
  if vim.v.vim_did_enter == 1 then
    fn()
  else
    nvim.autocmd('VimEnter', {
      callback = wrap_func(fn),
      once = true
    })
  end
end

--- Setup and start Gitsigns.
---
--- Attributes: ~
---     {async}
---
--- Parameters: ~
---     {cfg} Table object containing configuration for
---     Gitsigns. See |gitsigns-usage| for more details.
M.setup = void(function(cfg: Config)
  gs_config.build(cfg)

  if vim.fn.executable('git') == 0 then
    print('gitsigns: git not in path. Aborting setup')
    return
  end
  if config.yadm.enable and vim.fn.executable('yadm') == 0 then
    print("gitsigns: yadm not in path. Ignoring 'yadm.enable' in config")
    config.yadm.enable = false
    return
  end

  gs_debug.debug_mode = config.debug_mode
  gs_debug.verbose = config._verbose

  if config.debug_mode then
    for nm, f in pairs(gs_debug.add_debug_functions(cache)) do
      M0[nm] = f
    end
  end

  manager.setup()

  Status.formatter = config.status_formatter as function(Status.StatusObj): string

  -- Make sure highlights are setup on or after VimEnter so the colorscheme is
  -- loaded. Do not set them up with vim.schedule as this removes the intro
  -- message.
  on_or_after_vimenter(hl.setup_highlights)

  setup_command()

  git.enable_yadm = config.yadm.enable
  git.set_version(config._git_version)
  scheduler()

  -- Attach to all open buffers
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if    api.nvim_buf_is_loaded(buf)
      and api.nvim_buf_get_name(buf) ~= '' then
      M.attach(buf, 'setup')
      scheduler()
    end
  end

  nvim.augroup('gitsigns')

  autocmd('VimLeavePre' , M.detach_all)
  autocmd('ColorScheme' , hl.setup_highlights)
  autocmd('BufRead'     , wrap_func(M.attach, nil, 'BufRead'))
  autocmd('BufNewFile'  , wrap_func(M.attach, nil, 'BufNewFile'))
  autocmd('BufWritePost', wrap_func(M.attach, nil, 'BufWritePost'))

  autocmd('OptionSet', {
    pattern = 'fileformat',
    callback = function()
      require('gitsigns.actions').refresh()
    end}
  )

  -- vimpgrep creates and deletes lots of buffers so attaching to each one will
  -- waste lots of resource and even slow down vimgrep.
  autocmd('QuickFixCmdPre', {
    pattern ='*vimgrep*',
    callback = function()
      vimgrep_running = true
    end
  })

  autocmd('QuickFixCmdPost', {
    pattern ='*vimgrep*',
    callback = function()
      vimgrep_running = false
    end
  })

  require('gitsigns.current_line_blame').setup()

  scheduler()
  manager.update_cwd_head()
  -- Need to debounce in case some plugin changes the cwd too often
  -- (like vim-grepper)
  autocmd('DirChanged', debounce_trailing(100, manager.update_cwd_head))
end)

if _TEST then
  M.parse_fugitive_uri = parse_fugitive_uri
end

return setmetatable(M, {
  __index = function(_, f: string): any
    return (require('gitsigns.actions') as {string:function})[f]
  end
})
