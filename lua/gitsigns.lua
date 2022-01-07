local void = require('plenary.async.async').void
local scheduler = require('plenary.async.util').scheduler

local Status = require("gitsigns.status")
local git = require('gitsigns.git')
local manager = require('gitsigns.manager')
local signs = require('gitsigns.signs')
local util = require('gitsigns.util')

local gs_cache = require('gitsigns.cache')
local cache = gs_cache.cache
local CacheEntry = gs_cache.CacheEntry

local gs_config = require('gitsigns.config')
local Config = gs_config.Config
local config = gs_config.config

local gs_debug = require("gitsigns.debug")
local dprintf = gs_debug.dprintf
local dprint = gs_debug.dprint

local api = vim.api
local uv = vim.loop
local current_buf = api.nvim_get_current_buf

local M = {}














local namespace

local handle_moved = function(bufnr, bcache, old_relpath)
   local git_obj = bcache.git_obj
   local do_update = false

   local new_name = git_obj:has_moved()
   if new_name then
      dprintf('File moved to %s', new_name)
      git_obj.relpath = new_name
      if not git_obj.orig_relpath then
         git_obj.orig_relpath = old_relpath
      end
      do_update = true
   elseif git_obj.orig_relpath then
      local orig_file = git_obj.repo.toplevel .. util.path_sep .. git_obj.orig_relpath
      if git_obj:file_info(orig_file).relpath then
         dprintf('Moved file reset')
         git_obj.relpath = git_obj.orig_relpath
         git_obj.orig_relpath = nil
         do_update = true
      end
   else

   end

   if do_update then
      git_obj.file = git_obj.repo.toplevel .. util.path_sep .. git_obj.relpath
      bcache.file = git_obj.file
      git_obj:update_file_info()
      scheduler()
      api.nvim_buf_set_name(bufnr, bcache.file)
   end
end

local watch_gitdir = function(bufnr, gitdir)
   dprintf('Watching git dir')
   local w = uv.new_fs_poll()
   w:start(gitdir, config.watch_gitdir.interval, void(function(err)
      local __FUNC__ = 'watcher_cb'
      if err then
         dprintf('Git dir update error: %s', err)
         return
      end
      dprint('Git dir update')

      local bcache = cache[bufnr]

      if not bcache then



         dprint('Has detached, aborting')
         return
      end

      local git_obj = bcache.git_obj

      git_obj.repo:update_abbrev_head()

      scheduler()
      Status:update(bufnr, { head = git_obj.repo.abbrev_head })

      local was_tracked = git_obj.object_name ~= nil
      local old_relpath = git_obj.relpath

      if not git_obj:update_file_info() then
         dprint('File not changed')
         return
      end

      if config.watch_gitdir.follow_files and was_tracked and not git_obj.object_name then


         handle_moved(bufnr, bcache, old_relpath)
      end

      bcache.compare_text = nil

      manager.update(bufnr, bcache)
   end))
   return w
end


M.detach_all = function()
   for k, _ in pairs(cache) do
      M.detach(k)
   end
end






M.detach = function(bufnr, _keep_signs)






   bufnr = bufnr or current_buf()
   dprint('Detached')
   local bcache = cache[bufnr]
   if not bcache then
      dprint('Cache was nil')
      return
   end

   if not _keep_signs then
      signs.remove(bufnr)
   end


   Status:clear(bufnr)

   cache:destroy(bufnr)
end

local function get_buf_path(bufnr)
   local file = 
   uv.fs_realpath(api.nvim_buf_get_name(bufnr)) or

   api.nvim_buf_call(bufnr, function()
      return vim.fn.expand('%:p')
   end)

   if vim.startswith(file, 'fugitive://') and vim.wo.diff == false then
      local orig_path = file
      local _, _, root_path, sub_module_path, commit, real_path = 
      file:find([[^fugitive://(.*)/%.git(.*)/(%x-)/(.*)]])
      if root_path then
         sub_module_path = sub_module_path:gsub("^/modules", "")
         file = root_path .. sub_module_path .. real_path
         file = uv.fs_realpath(file)
         dprintf("Fugitive buffer for file '%s' from path '%s'", file, orig_path)
         if file then
            return file, commit
         else
            file = orig_path
         end
      end
   end

   return file
end

local attach_disabled = false

local attach0 = function(cbuf, aucmd)
   if attach_disabled then
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

   local file_dir = util.dirname(file)

   if not file_dir or not util.path_exists(file_dir) then
      dprint('Not a path')
      return
   end

   local git_obj = git.Obj.new(file)
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



   scheduler()

   if config.on_attach and config.on_attach(cbuf) == false then
      dprint('User on_attach() returned false')
      return
   end

   cache[cbuf] = CacheEntry.new({
      base = config.base,
      file = file,
      commit = commit,
      gitdir_watcher = watch_gitdir(cbuf, repo.gitdir),
      git_obj = git_obj,
   })


   manager.update(cbuf, cache[cbuf])

   scheduler()

   api.nvim_buf_attach(cbuf, false, {
      on_lines = function(_, buf, _, first, last_orig, last_new, byte_count)
         if first == last_orig and last_orig == last_new and byte_count == 0 then


            return
         end
         return manager.on_lines(buf, last_orig, last_new)
      end,
      on_reload = function(_, bufnr)
         local __FUNC__ = 'on_reload'
         dprint('Reload')
         manager.update_debounced(bufnr)
      end,
      on_detach = function(_, buf)
         M.detach(buf, true)
      end,
   })

   if config.keymaps and not vim.tbl_isempty(config.keymaps) then
      require('gitsigns.mappings')(config.keymaps, cbuf)
   end
end

M._attach_enable = function()
   attach_disabled = false
end

M._attach_disable = function()
   attach_disabled = true
end




local attach_running = {}

local attach = function(cbuf, trigger)
   cbuf = cbuf or current_buf()
   if attach_running[cbuf] then
      dprint('Attach in progress')
      return
   end
   attach_running[cbuf] = true
   attach0(cbuf, trigger)
   attach_running[cbuf] = nil
end








M.attach = void(attach)

local M0 = M

M._complete = function(arglead, line)
   local n = #vim.split(line, '%s+')

   local matches = {}
   if n == 2 then
      local actions = require('gitsigns.actions')
      for _, m in ipairs({ actions, M0 }) do
         for func, _ in pairs(m) do
            if vim.startswith(func, '_') then

            elseif vim.startswith(func, arglead) then
               table.insert(matches, func)
            end
         end
      end
   end
   return matches
end








local function parse_args_to_lua(...)
   local args = {}
   for i, a in ipairs({ ... }) do
      if tonumber(a) then
         args[i] = tonumber(a)
      elseif a == 'false' or a == 'true' then
         args[i] = a == 'true'
      elseif a == 'nil' then
         args[i] = nil
      else
         args[i] = a
      end
   end
   return args
end

M._run_func = function(range, func, ...)
   local actions = require('gitsigns.actions')
   local actions0 = actions

   local args = parse_args_to_lua(...)

   if type(actions0[func]) == 'function' then
      if range and range[1] > 0 then
         actions.user_range = { range[2], range[3] }
      else
         actions.user_range = nil
      end
      actions0[func](unpack(args))
      actions.user_range = nil
      return
   end
   if type(M0[func]) == 'function' then
      M0[func](unpack(args))
      return
   end
end

local _update_cwd_head = function()
   local cwd = vim.fn.getcwd()
   local head
   for _, bcache in pairs(cache) do
      local repo = bcache.git_obj.repo
      if repo.toplevel == cwd then
         head = repo.abbrev_head
         break
      end
   end
   if not head then
      _, _, head = git.get_repo_info(cwd)
      scheduler()
   end
   if head then
      api.nvim_set_var('gitsigns_head', head)
   else
      pcall(api.nvim_del_var, 'gitsigns_head')
   end
end

M._update_cwd_head = void(_update_cwd_head)

local function setup_command()
   if api.nvim_add_user_command then
      api.nvim_add_user_command('Gitsigns', function(params)
         local fargs = vim.split(params.args, '%s+')
         M._run_func({ params.range, params.line1, params.line2 }, unpack(fargs))
      end, {
         force = true,
         nargs = '+',
         range = true,
         complete = M._complete,
      })
   else
      vim.cmd(table.concat({
         'command!',
         '-range',
         '-nargs=+',
         '-complete=customlist,v:lua.package.loaded.gitsigns._complete',
         'Gitsigns',
         'lua require("gitsigns")._run_func({<range>, <line1>, <line2>}, <f-args>)',
      }, ' '))
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

   namespace = api.nvim_create_namespace('gitsigns')

   gs_debug.debug_mode = config.debug_mode
   gs_debug.verbose = config._verbose

   if config.debug_mode then
      for nm, f in pairs(gs_debug.add_debug_functions(cache)) do
         M0[nm] = f
      end
   end

   manager.setup()

   Status.formatter = config.status_formatter




   if vim.v.vim_did_enter == 1 then
      manager.setup_signs_and_highlights()
   else
      vim.cmd([[autocmd VimEnter * ++once lua require('gitsigns.manager').setup_signs_and_highlights()]])
   end

   setup_command()



   api.nvim_set_decoration_provider(namespace, {
      on_win = function(_, _, bufnr, top, bot)
         local bcache = cache[bufnr]
         if not bcache or not bcache.pending_signs then
            return false
         end
         manager.apply_win_signs(bufnr, bcache.pending_signs, top + 1, bot + 1)


         return config.word_diff and config.diff_opts.internal
      end,
      on_line = function(_, _, bufnr, row)
         manager.apply_word_diff(bufnr, row)
      end,
   })

   git.enable_yadm = config.yadm.enable
   git.set_version(config._git_version)
   scheduler()


   for _, buf in ipairs(api.nvim_list_bufs()) do
      if api.nvim_buf_is_loaded(buf) and
         api.nvim_buf_get_name(buf) ~= '' then
         attach(buf, 'setup')
         scheduler()
      end
   end

   vim.cmd([[
    augroup gitsigns
      autocmd!
      autocmd VimLeavePre  * lua _G.package.loaded.gitsigns.detach_all()
      autocmd ColorScheme  * lua _G.package.loaded.gitsigns._update_highlights()
      autocmd BufRead      * lua _G.package.loaded.gitsigns.attach(nil, 'BufRead')
      autocmd BufNewFile   * lua _G.package.loaded.gitsigns.attach(nil, 'BufNewFile')
      autocmd BufWritePost * lua _G.package.loaded.gitsigns.attach(nil, 'BufWritePost')

      autocmd OptionSet fileformat lua _G.package.loaded.gitsigns.refresh()

      " vimpgrep creates and deletes lots of buffers so attaching to each one will
      " waste lots of resource and even slow down vimgrep.
      autocmd QuickFixCmdPre  *vimgrep* lua _G.package.loaded.gitsigns._attach_disable()
      autocmd QuickFixCmdPost *vimgrep* lua _G.package.loaded.gitsigns._attach_enable()
    augroup END
  ]])

   require('gitsigns.current_line_blame').setup()

   scheduler()
   M._update_cwd_head()
   vim.cmd([[autocmd gitsigns DirChanged * lua _G.package.loaded.gitsigns._update_cwd_head()]])
end)


M._update_highlights = function()
   manager.setup_signs_and_highlights()
end

setmetatable(M, {
   __index = function(_, f)
      return (require('gitsigns.actions'))[f]
   end,
})

return M
