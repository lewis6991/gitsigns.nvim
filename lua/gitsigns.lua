local a = require('plenary.async')
local void = a.void
local scheduler = a.util.scheduler

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
      dprint('File moved to ' .. new_name)
      git_obj.relpath = new_name
      if not git_obj.orig_relpath then
         git_obj.orig_relpath = old_relpath
      end
      do_update = true
   elseif git_obj.orig_relpath then
      local orig_file = git_obj.toplevel .. util.path_sep .. git_obj.orig_relpath
      if git_obj:file_info(orig_file) then
         dprint('Moved file reset')
         git_obj.relpath = git_obj.orig_relpath
         git_obj.orig_relpath = nil
         do_update = true
      end
   else

   end

   if do_update then
      git_obj.file = git_obj.toplevel .. util.path_sep .. git_obj.relpath
      bcache.file = git_obj.file
      bcache.git_obj:update_file_info()
      scheduler()
      api.nvim_buf_set_name(bufnr, bcache.file)
   end
end

local watch_index = function(bufnr, gitdir)
   dprint('Watching index')
   local index = gitdir .. util.path_sep .. 'index'
   local w = uv.new_fs_poll()
   w:start(index, config.watch_index.interval, void(function(err)
      if err then
         dprint('Index update error: ' .. err, 'watcher_cb')
         return
      end
      dprint('Index update', 'watcher_cb')

      local bcache = cache[bufnr]

      if not bcache then



         dprint(string.format('Buffer %s has detached, aborting', bufnr))
         return
      end

      local git_obj = bcache.git_obj

      git_obj:update_abbrev_head()

      scheduler()
      Status:update(bufnr, { head = git_obj.abbrev_head })

      local was_tracked = git_obj.object_name ~= nil
      local old_relpath = git_obj.relpath

      if not git_obj:update_file_info() then
         dprint('File not changed', 'watcher_cb')
         return
      end

      if config.watch_index.follow_files and was_tracked and not git_obj.object_name then


         handle_moved(bufnr, bcache, old_relpath)
      end

      bcache.compare_text = nil

      manager.update(bufnr, bcache)
   end))
   return w
end







M.detach = function(bufnr, keep_signs)
   bufnr = bufnr or current_buf()
   dprint('Detached')
   local bcache = cache[bufnr]
   if not bcache then
      dprint('Cache was nil')
      return
   end

   if not keep_signs then
      signs.remove(bufnr)
   end


   Status:clear(bufnr)

   cache:destroy(bufnr)
end

M.detach_all = function()
   for k, _ in pairs(cache) do
      M.detach(k)
   end
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
         dprint(("Fugitive buffer for file '%s' from path '%s'"):format(file, orig_path))
         if file then
            return file, commit
         else
            file = orig_path
         end
      end
   end

   return file
end

local function in_git_dir(file)
   for _, p in ipairs(vim.split(file, util.path_sep)) do
      if p == '.git' then
         return true
      end
   end
   return false
end

local attach0 = function(cbuf)
   if cache[cbuf] then
      dprint('Already attached')
      return
   end
   dprint('Attaching')

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

   if in_git_dir(file) then
      dprint('In git dir')
      return
   end

   local file_dir = util.dirname(file)

   if not file_dir or not util.path_exists(file_dir) then
      dprint('Not a path')
      return
   end

   local git_obj = git.Obj.new(file)

   if not git_obj.gitdir then
      dprint('Not in git repo')
      return
   end

   scheduler()
   Status:update(cbuf, {
      head = git_obj.abbrev_head,
      root = git_obj.toplevel,
      gitdir = git_obj.gitdir,
   })

   if vim.startswith(file, git_obj.gitdir .. util.path_sep) then
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
      file = file,
      commit = commit,
      index_watcher = watch_index(cbuf, git_obj.gitdir),
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
         dprint('Reload', 'on_reload')
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




local attach_running = {}

local attach = function(cbuf)
   cbuf = cbuf or current_buf()
   if attach_running[cbuf] then
      dprint('Attach in progress', 'attach')
      return
   end
   attach_running[cbuf] = true
   attach0(cbuf)
   attach_running[cbuf] = nil
end

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

M._run_func = function(range, func, ...)
   local actions = require('gitsigns.actions')
   local actions0 = actions
   if type(actions0[func]) == 'function' then
      if range and range[1] ~= range[2] then
         actions.user_range = range
      else
         actions.user_range = nil
      end
      actions0[func](...)
      actions.user_range = nil
      return
   end
   if type(M0[func]) == 'function' then
      M0[func](...)
      return
   end
end

local function setup_command()
   vim.cmd(table.concat({
      'command!',
      '-range',
      '-nargs=+',
      '-complete=customlist,v:lua.package.loaded.gitsigns._complete',
      'Gitsigns',
      'lua require("gitsigns")._run_func({<line1>, <line2>}, <f-args>)',
   }, ' '))
end

M.setup = void(function(cfg)
   gs_config.build(cfg)
   namespace = api.nvim_create_namespace('gitsigns')

   gs_debug.debug_mode = config.debug_mode

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

   if config.use_decoration_api then


      api.nvim_set_decoration_provider(namespace, {
         on_win = function(_, _, bufnr, top, bot)
            local bcache = cache[bufnr]
            if not bcache or not bcache.pending_signs then
               return false
            end
            manager.apply_win_signs(bufnr, bcache.pending_signs, top + 1, bot + 1)


            return config.word_diff and config.use_internal_diff
         end,
         on_line = function(_, _, bufnr, row)
            manager.apply_word_diff(bufnr, row)
         end,
      })
   end

   git.enable_yadm = config.yadm.enable
   git.set_version(config._git_version)
   scheduler()


   for _, buf in ipairs(api.nvim_list_bufs()) do
      if api.nvim_buf_is_loaded(buf) and
         api.nvim_buf_get_name(buf) ~= '' then
         attach(buf)
         scheduler()
      end
   end


   vim.cmd('augroup gitsigns | autocmd! | augroup END')

   for func, events in pairs({
         attach = 'BufRead,BufNewFile,BufWritePost',
         detach_all = 'VimLeavePre',
         _update_highlights = 'ColorScheme',
      }) do
      vim.cmd('autocmd gitsigns ' .. events .. ' * lua require("gitsigns").' .. func .. '()')
   end

   require('gitsigns.current_line_blame').setup()
end)

M.attach = void(attach)


M._get_config = function()
   return config
end

M._update_highlights = function()
   manager.setup_signs_and_highlights()
end

setmetatable(M, {
   __index = function(_, f)
      return (require('gitsigns.actions'))[f]
   end,
})

return M
