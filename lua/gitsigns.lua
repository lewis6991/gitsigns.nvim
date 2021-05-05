local a = require('plenary.async_lib.async')
local void = a.void
local await = a.await
local async = a.async
local async_void = a.async_void
local scheduler = a.scheduler

local Status = require("gitsigns.status")
local apply_mappings = require('gitsigns.mappings')
local git = require('gitsigns.git')
local gs_hl = require('gitsigns.highlight')
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

local watch_index = function(bufnr, gitdir)
   dprint('Watching index', bufnr, 'watch_index')
   local index = gitdir .. util.path_sep .. 'index'
   local w = uv.new_fs_poll()
   w:start(index, config.watch_index.interval, async_void(function(err)
      if err then
         dprint('Index update error: ' .. err, bufnr, 'watcher_cb')
         return
      end
      dprint('Index update', bufnr, 'watcher_cb')

      local bcache = cache[bufnr]

      if not bcache then



         dprint(string.format('Buffer %s has detached, aborting', bufnr))
         return
      end

      local git_obj = bcache.git_obj

      await(git_obj:update_abbrev_head())

      await(scheduler())
      Status:update_head(bufnr, git_obj.abbrev_head)

      if not await(git_obj:update_file_info()) then
         dprint('File not changed', bufnr, 'watcher_cb')
         return
      end

      bcache.compare_text = nil

      await(manager.update(bufnr))
   end))
   return w
end







local function detach(bufnr, keep_signs)
   bufnr = bufnr or current_buf()
   dprint('Detached', bufnr)
   local bcache = cache[bufnr]
   if not bcache then
      dprint('Cache was nil', bufnr)
      return
   end

   if not keep_signs then
      signs.remove(bufnr)
   end


   Status:clear(bufnr)

   cache:destroy(bufnr)
end

local function detach_all()
   for k, _ in pairs(cache) do
      detach(k)
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
         dprint(("Fugitive buffer for file '%s' from path '%s'"):format(file, orig_path), bufnr)
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

local attach = async(function(cbuf)
   await(scheduler())
   cbuf = cbuf or current_buf()
   if cache[cbuf] then
      dprint('Already attached', cbuf, 'attach')
      return
   end
   dprint('Attaching', cbuf, 'attach')

   if not api.nvim_buf_is_loaded(cbuf) then
      dprint('Non-loaded buffer', cbuf, 'attach')
      return
   end

   if api.nvim_buf_line_count(cbuf) > config.max_file_length then
      dprint('Exceeds max_file_length', cbuf, 'attach')
      return
   end

   if api.nvim_buf_get_option(cbuf, 'buftype') ~= '' then
      dprint('Non-normal buffer', cbuf, 'attach')
      return
   end

   local file, commit = get_buf_path(cbuf)

   if in_git_dir(file) then
      dprint('In git dir', cbuf, 'attach')
      return
   end

   local file_dir = util.dirname(file)

   if not file_dir or not util.path_exists(file_dir) then
      dprint('Not a path', cbuf, 'attach')
      return
   end

   local git_obj = await(git.Obj.new(file))

   if not git_obj.gitdir then
      dprint('Not in git repo', cbuf, 'attach')
      return
   end

   await(scheduler())
   Status:update_head(cbuf, git_obj.abbrev_head)

   if vim.startswith(file, git_obj.gitdir) then
      dprint('In non-standard git dir', cbuf, 'attach')
      return
   end

   if not util.path_exists(file) or uv.fs_stat(file).type == 'directory' then
      dprint('Not a file', cbuf, 'attach')
      return
   end

   if not git_obj.relpath then
      dprint('Cannot resolve file in repo', cbuf, 'attach')
      return
   end

   if not config.attach_to_untracked and git_obj.object_name == nil then
      dprint('File is untracked', cbuf, 'attach')
      return
   end



   await(scheduler())

   cache[cbuf] = CacheEntry.new({
      file = file,
      commit = commit,
      index_watcher = watch_index(cbuf, git_obj.gitdir),
      git_obj = git_obj,
   })


   await(manager.update(cbuf))

   await(scheduler())

   api.nvim_buf_attach(cbuf, false, {
      on_lines = function(_, buf, _, first, last_orig, last_new, byte_count)
         if first == last_orig and last_orig == last_new and byte_count == 0 then


            return
         end
         return manager.on_lines(buf, last_orig, last_new)
      end,
      on_reload = function(_, buf)
         dprint('Reload', buf, 'on_reload')
         manager.update_debounced(buf)
      end,
      on_detach = function(_, buf)
         detach(buf, true)
      end,
   })

   apply_mappings(config.keymaps, true)
end)

local function setup_signs_and_highlights(redefine)

   for t, sign_name in pairs(signs.sign_map) do
      local cs = config.signs[t]

      gs_hl.setup_highlight(cs.hl)

      local HlTy = {}
      for _, hlty in ipairs({ 'numhl', 'linehl' }) do
         if config[hlty] then
            gs_hl.setup_other_highlight(cs[hlty], cs.hl)
         end
      end

      signs.define(sign_name, {
         texthl = cs.hl,
         text = config.signcolumn and cs.text or nil,
         numhl = config.numhl and cs.numhl,
         linehl = config.linehl and cs.linehl,
      }, redefine)

   end
   if config.current_line_blame then
      gs_hl.setup_highlight('GitSignsCurrentLineBlame')
   end
end


local function _complete(arglead, line)
   local n = #vim.split(line, '%s+')

   local matches = {}
   if n == 2 then
      local function get_matches(t)
         for func, _ in pairs(t) do
            if vim.startswith(func, '_') then

            elseif vim.startswith(func, arglead) then
               table.insert(matches, func)
            end
         end
      end

      get_matches(require('gitsigns.actions'))
      get_matches(M)
   end
   return matches
end

local function _run_func(func, ...)
   local actions = require('gitsigns.actions')
   if type(actions[func]) == 'function' then
      actions[func](...)
      return
   end
   if type(M[func]) == 'function' then
      M[func](...)
      return
   end
end

local function setup_command()
   vim.cmd(table.concat({
      'command!',
      '-nargs=+',
      '-complete=customlist,v:lua.package.loaded.gitsigns._complete',
      'Gitsigns',
      'lua require("gitsigns")._run_func(<f-args>)',
   }, ' '))
end

local function setup_current_line_blame()
   require('gitsigns.current_line_blame').setup()
end

local setup = async_void(function(cfg)
   gs_config.build(cfg)
   namespace = api.nvim_create_namespace('gitsigns')

   gs_debug.debug_mode = config.debug_mode

   if config.debug_mode then
      for nm, f in pairs(gs_debug.add_debug_functions(cache)) do
         M[nm] = f
      end
   end

   manager.setup()

   Status.formatter = config.status_formatter

   setup_signs_and_highlights()
   setup_command()
   apply_mappings(config.keymaps, false)

   if config.use_decoration_api then


      api.nvim_set_decoration_provider(namespace, {
         on_win = function(_, _, bufnr, top, bot)
            local bcache = cache[bufnr]
            if not bcache or not bcache.pending_signs then
               return
            end
            manager.apply_win_signs(bufnr, bcache.pending_signs, top + 1, bot + 1)
         end,
      })
   end

   git.enable_yadm = config.yadm.enable
   await(git.set_version(config._git_version))
   await(scheduler())


   for _, buf in ipairs(api.nvim_list_bufs()) do
      if api.nvim_buf_is_loaded(buf) and
         api.nvim_buf_get_name(buf) ~= '' then
         await(attach(buf))
         await(scheduler())
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

   setup_current_line_blame()
end)

local function refresh()
   setup_signs_and_highlights(true)
   setup_current_line_blame()
   for k, v in pairs(cache) do
      v.compare_text = nil
      void(manager.update)(k, v)
   end
end

local function toggle_signs()
   config.signcolumn = not config.signcolumn
   refresh()
end

local function toggle_numhl()
   config.numhl = not config.numhl
   refresh()
end

local function toggle_linehl()
   config.linehl = not config.linehl
   refresh()
end

local function toggle_current_line_blame()
   config.current_line_blame = not config.current_line_blame
   refresh()
end

M = {
   attach = void(attach),
   detach = detach,
   detach_all = detach_all,
   setup = setup,
   refresh = refresh,
   toggle_signs = toggle_signs,
   toggle_linehl = toggle_linehl,
   toggle_numhl = toggle_numhl,


   _get_config = function()
      return config
   end,

   _complete = _complete,
   _run_func = _run_func,

   toggle_current_line_blame = toggle_current_line_blame,

   _update_highlights = function()
      setup_signs_and_highlights()
   end,
}

setmetatable(M, {
   __index = function(_, f)
      return (require('gitsigns.actions'))[f]
   end,
})

return M
