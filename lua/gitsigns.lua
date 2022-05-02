local void = require('gitsigns.async').void
local scheduler = require('gitsigns.async').scheduler

local Status = require("gitsigns.status")
local git = require('gitsigns.git')
local manager = require('gitsigns.manager')
local nvim = require('gitsigns.nvim')
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

local M = {}










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

   manager.detach(bufnr, _keep_signs)


   Status:clear(bufnr)

   cache:destroy(bufnr)
end

local function parse_fugitive_uri(name)
   local _, _, root_path, sub_module_path, commit, real_path = 
   name:find([[^fugitive://(.*)/%.git(.*/)/(%x-)/(.*)]])
   if commit == '0' then

      commit = nil
   end
   if root_path then
      sub_module_path = sub_module_path:gsub("^/modules", "")
      name = root_path .. sub_module_path .. real_path
   end
   return name, commit
end

local function get_buf_path(bufnr)
   local file = 
   uv.fs_realpath(api.nvim_buf_get_name(bufnr)) or

   api.nvim_buf_call(bufnr, function()
      return vim.fn.expand('%:p')
   end)

   if vim.startswith(file, 'fugitive://') and vim.wo.diff == false then
      local path, commit = parse_fugitive_uri(file)
      dprintf("Fugitive buffer for file '%s' from path '%s'", path, file)
      path = uv.fs_realpath(path)
      if path then
         return path, commit
      end
   end

   return file
end

local vimgrep_running = false

local function on_lines(_, bufnr, _, first, last_orig, last_new, byte_count)
   if first == last_orig and last_orig == last_new and byte_count == 0 then


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




local attach_throttled = throttle_by_id(function(cbuf, aucmd)
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

   local file_dir = util.dirname(file)

   if not file_dir or not util.path_exists(file_dir) then
      dprint('Not a path')
      return
   end

   local git_obj = git.Obj.new(file, vim.bo[cbuf].fileencoding)
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
      gitdir_watcher = manager.watch_gitdir(cbuf, repo.gitdir),
      git_obj = git_obj,
   })


   manager.update(cbuf, cache[cbuf])

   scheduler()

   api.nvim_buf_attach(cbuf, false, {
      on_lines = on_lines,
      on_reload = on_reload,
      on_detach = on_detach,
   })

   if config.keymaps and not vim.tbl_isempty(config.keymaps) then
      require('gitsigns.mappings')(config.keymaps, cbuf)
   end
end)








M.attach = void(function(bufnr, _trigger)
   attach_throttled(bufnr or current_buf(), _trigger)
end)

local M0 = M

local function complete(arglead, line)
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

local function run_func(range, func, ...)
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

local function setup_command()
   nvim.command('Gitsigns', function(params)
      local fargs = require('gitsigns.argparse').parse_args(params.args)
      run_func({ params.range, params.line1, params.line2 }, unpack(fargs))
   end, { force = true, nargs = '+', range = true, complete = complete })
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
   nvim.autocmd(event, opts0)
end

local function on_or_after_vimenter(fn)
   if vim.v.vim_did_enter == 1 then
      fn()
   else
      nvim.autocmd('VimEnter', {
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
         M0[nm] = f
      end
   end

   manager.setup()

   Status.formatter = config.status_formatter




   on_or_after_vimenter(hl.setup_highlights)

   setup_command()

   git.enable_yadm = config.yadm.enable
   git.set_version(config._git_version)
   scheduler()


   for _, buf in ipairs(api.nvim_list_bufs()) do
      if api.nvim_buf_is_loaded(buf) and
         api.nvim_buf_get_name(buf) ~= '' then
         M.attach(buf, 'setup')
         scheduler()
      end
   end

   nvim.augroup('gitsigns')

   autocmd('VimLeavePre', M.detach_all)
   autocmd('ColorScheme', hl.setup_highlights)
   autocmd('BufRead', wrap_func(M.attach, nil, 'BufRead'))
   autocmd('BufNewFile', wrap_func(M.attach, nil, 'BufNewFile'))
   autocmd('BufWritePost', wrap_func(M.attach, nil, 'BufWritePost'))

   autocmd('OptionSet', {
      pattern = 'fileformat',
      callback = function()
         require('gitsigns.actions').refresh()
      end, })




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


   autocmd('DirChanged', debounce_trailing(100, manager.update_cwd_head))
end)

if _TEST then
   M.parse_fugitive_uri = parse_fugitive_uri
end

return setmetatable(M, {
   __index = function(_, f)
      return (require('gitsigns.actions'))[f]
   end,
})
