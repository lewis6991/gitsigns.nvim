local async = require('gitsigns.async')
local void = require('gitsigns.async').void
local scheduler = require('gitsigns.async').scheduler

local Status = require("gitsigns.status")
local git = require('gitsigns.git')
local manager = require('gitsigns.manager')
local util = require('gitsigns.util')
local hl = require('gitsigns.highlight')

local gs_cache = require('gitsigns.cache')
local cache = gs_cache.cache
local CacheEntry = gs_cache.CacheEntry

local gs_config = require('gitsigns.config')
local Config = gs_config.Config
local config = gs_config.config

local gs_debug = require("gitsigns.debug")
local dprintf = gs_debug.dprintf
local dprint = gs_debug.dprint

local Debounce = require("gitsigns.debounce")
local debounce_trailing = Debounce.debounce_trailing
local throttle_by_id = Debounce.throttle_by_id

local api = vim.api
local uv = vim.loop
local current_buf = api.nvim_get_current_buf

local M = {GitContext = {}, }














local GitContext = M.GitContext


function M.detach_all()
   for k, _ in pairs(cache) do
      M.detach(k)
   end
end






function M.detach(bufnr, _keep_signs)
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


local function parse_fugitive_uri(name)
   if vim.fn.exists('*FugitiveReal') == 0 then
      dprint("Fugitive not installed")
      return
   end

   local path = vim.fn.FugitiveReal(name)
   local commit = vim.fn.FugitiveParse(name)[1]:match('([^:]+):.*')
   if commit == '0' then
      -- '0' means the index so clear commit so we attach normally
      commit = nil
   end
   return path, commit
end

local function parse_gitsigns_uri(name)
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

local function get_buf_path(bufnr)
   local file = 
   uv.fs_realpath(api.nvim_buf_get_name(bufnr)) or

   api.nvim_buf_call(bufnr, function()
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

local function on_lines(_, bufnr, _, first, last_orig, last_new, byte_count)
   if first == last_orig and last_orig == last_new and byte_count == 0 then
      -- on_lines can be called twice for undo events; ignore the second
      -- call which indicates no changes.
      return
   end
   return manager.on_lines(bufnr, first, last_orig, last_new)
end

local function on_reload(_, bufnr)
   local __FUNC__ = 'on_reload'
   dprint('Reload')
   manager.update_debounced(bufnr)
end

local function on_detach(_, bufnr)
   M.detach(bufnr, true)
end

local function on_attach_pre(bufnr)
   local gitdir, toplevel
   if config._on_attach_pre then
      local res = async.wrap(config._on_attach_pre, 2)(bufnr)
      dprintf('ran on_attach_pre with result %s', vim.inspect(res))
      if type(res) == "table" then
         if type(res.gitdir) == 'string' then
            gitdir = res.gitdir
         end
         if type(res.toplevel) == 'string' then
            toplevel = res.toplevel
         end
      end
   end
   return gitdir, toplevel
end

local function try_worktrees(_bufnr, file, encoding)
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




local attach_throttled = throttle_by_id(function(cbuf, ctx, aucmd)
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

   local encoding = vim.bo[cbuf].fileencoding
   if encoding == '' then
      encoding = 'utf-8'
   end
   local file
   local commit
   local gitdir_oap
   local toplevel_oap

   if ctx then
      gitdir_oap = ctx.gitdir
      toplevel_oap = ctx.toplevel
      file = ctx.toplevel .. util.path_sep .. ctx.file
      commit = ctx.commit
   else
      if api.nvim_buf_line_count(cbuf) > config.max_file_length then
         dprint('Exceeds max_file_length')
         return
      end

      if vim.bo[cbuf].buftype ~= '' then
         dprint('Non-normal buffer')
         return
      end

      file, commit = get_buf_path(cbuf)
      local file_dir = util.dirname(file)

      if not file_dir or not util.path_exists(file_dir) then
         dprint('Not a path')
         return
      end

      gitdir_oap, toplevel_oap = on_attach_pre(cbuf)
   end

   local git_obj = git.Obj.new(file, encoding, gitdir_oap, toplevel_oap)

   if not git_obj and not ctx then
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
      head = repo.abbrev_head,
      root = repo.toplevel,
      gitdir = repo.gitdir,
   })

   if vim.startswith(file, repo.gitdir .. util.path_sep) then
      dprint('In non-standard git dir')
      return
   end

   if not ctx and (not util.path_exists(file) or uv.fs_stat(file).type == 'directory') then
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

   cache[cbuf] = CacheEntry.new({
      base = ctx and ctx.base or config.base,
      file = file,
      commit = commit,
      gitdir_watcher = manager.watch_gitdir(cbuf, repo.gitdir),
      git_obj = git_obj,
   })

   if not api.nvim_buf_is_loaded(cbuf) then
      dprint('Un-loaded buffer')
      return
   end

   -- Make sure to attach before the first update (which is async) so we pick up
   -- changes from BufReadCmd.
   api.nvim_buf_attach(cbuf, false, {
      on_lines = on_lines,
      on_reload = on_reload,
      on_detach = on_detach,
   })

   -- Initial update
   manager.update(cbuf, cache[cbuf])

   if config.keymaps and not vim.tbl_isempty(config.keymaps) then
      require('gitsigns.mappings')(config.keymaps, cbuf)
   end
end)























M.attach = void(function(bufnr, ctx, _trigger)
   attach_throttled(bufnr or current_buf(), ctx, _trigger)
end)

local function setup_cli()
   local funcs = M
   api.nvim_create_user_command('Gitsigns', function(params)
      require('gitsigns.cli').run(funcs, params)
   end, {
      force = true,
      nargs = '*',
      range = true,
      complete = function(arglead, line)
         return require('gitsigns.cli').complete(funcs, arglead, line)
      end, })
end

local function wrap_func(fn, ...)
   local args = { ... }
   local nargs = select('#', ...)
   return function()
      fn(unpack(args, 1, nargs))
   end
end

local function autocmd(event, opts)
   local opts0 = {}
   if type(opts) == "function" then
      opts0.callback = wrap_func(opts)
   else
      opts0 = opts
   end
   opts0.group = 'gitsigns'
   api.nvim_create_autocmd(event, opts0)
end

local function on_or_after_vimenter(fn)
   if vim.v.vim_did_enter == 1 then
      fn()
   else
      api.nvim_create_autocmd('VimEnter', {
         callback = wrap_func(fn),
         once = true,
      })
   end
end









M.setup = void(function(cfg)
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
         (M)[nm] = f
      end
   end

   manager.setup()

   Status.formatter = config.status_formatter

   -- Make sure highlights are setup on or after VimEnter so the colorscheme is
   -- loaded. Do not set them up with vim.schedule as this removes the intro
   -- message.
   on_or_after_vimenter(hl.setup_highlights)

   setup_cli()

   git.enable_yadm = config.yadm.enable
   git.set_version(config._git_version)
   scheduler()

   -- Attach to all open buffers
   for _, buf in ipairs(api.nvim_list_bufs()) do
      if api.nvim_buf_is_loaded(buf) and
         api.nvim_buf_get_name(buf) ~= '' then
         M.attach(buf, nil, 'setup')
         scheduler()
      end
   end

   api.nvim_create_augroup('gitsigns', {})

   autocmd('VimLeavePre', M.detach_all)
   autocmd('ColorScheme', hl.setup_highlights)
   autocmd('BufRead', wrap_func(M.attach, nil, nil, 'BufRead'))
   autocmd('BufNewFile', wrap_func(M.attach, nil, nil, 'BufNewFile'))
   autocmd('BufWritePost', wrap_func(M.attach, nil, nil, 'BufWritePost'))

   autocmd('OptionSet', {
      pattern = 'fileformat',
      callback = function()
         require('gitsigns.actions').refresh()
      end, })


   -- vimpgrep creates and deletes lots of buffers so attaching to each one will
   -- waste lots of resource and even slow down vimgrep.
   autocmd('QuickFixCmdPre', {
      pattern = '*vimgrep*',
      callback = function()
         vimgrep_running = true
      end,
   })

   autocmd('QuickFixCmdPost', {
      pattern = '*vimgrep*',
      callback = function()
         vimgrep_running = false
      end,
   })

   require('gitsigns.current_line_blame').setup()

   scheduler()
   manager.update_cwd_head()
   -- Need to debounce in case some plugin changes the cwd too often
   -- (like vim-grepper)
   autocmd('DirChanged', debounce_trailing(100, manager.update_cwd_head))
end)

return setmetatable(M, {
   __index = function(_, f)
      return (require('gitsigns.actions'))[f]
   end,
})
