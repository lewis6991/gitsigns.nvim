local a = require('plenary.async')
local JobSpec = require('plenary.job').JobSpec

local gsd = require("gitsigns.debug")
local util = require('gitsigns.util')

local gs_hunks = require("gitsigns.hunks")
local Hunk = gs_hunks.Hunk

local uv = vim.loop
local startswith = vim.startswith

local GJobSpec = {}












local M = {BlameInfo = {}, Version = {}, Obj = {}, }





























































local Obj = M.Obj

local function parse_version(version)
   assert(version:match('%d+%.%d+%.%w+'), 'Invalid git version: ' .. version)
   local ret = {}
   local parts = vim.split(version, '%.')
   ret.major = tonumber(parts[1])
   ret.minor = tonumber(parts[2])

   if parts[3] == 'GIT' then
      ret.patch = 0
   else
      ret.patch = tonumber(parts[3])
   end

   return ret
end


local function check_version(version)
   if M.version.major < version[1] then
      return false
   end
   if version[2] and M.version.minor < version[2] then
      return false
   end
   if version[3] and M.version.patch < version[3] then
      return false
   end
   return true
end

local command = a.wrap(function(args, spec, callback)
   local result = {}
   local reserr
   spec = spec or {}
   spec.command = spec.command or 'git'
   spec.args = { '--no-pager', unpack(args) }
   spec.on_stdout = spec.on_stdout or function(_, line)
      table.insert(result, line)
   end
   spec.on_stderr = spec.on_stderr or function(err, line)
      if not spec.supress_stderr then
         if err then gsd.eprint(err) end
         if line then gsd.eprint(line) end
      end
      if not reserr then
         reserr = ''
      else
         reserr = reserr .. '\n'
      end
      if err then reserr = reserr .. err end
      if line then reserr = reserr .. line end
   end
   local old_on_exit = spec.on_exit
   spec.on_exit = function()
      if old_on_exit then
         old_on_exit()
      end
      callback(result, reserr)
   end
   util.run_job(spec)
end, 3)

local function process_abbrev_head(gitdir, head_str)
   if not gitdir then
      return head_str
   end
   if head_str == 'HEAD' then
      if util.path_exists(gitdir .. '/rebase-merge') or
         util.path_exists(gitdir .. '/rebase-apply') then
         return '(rebasing)'
      elseif gsd.debug_mode then
         return head_str
      else
         return ''
      end
   end
   return head_str
end

local get_repo_info = function(path, cmd)


   local has_abs_gd = check_version({ 2, 13 })
   local git_dir_opt = has_abs_gd and '--absolute-git-dir' or '--git-dir'



   a.util.scheduler()

   local results = command({
      'rev-parse', '--show-toplevel', git_dir_opt, '--abbrev-ref', 'HEAD',
   }, {
      command = cmd or 'git',
      supress_stderr = true,
      cwd = path,
   })

   local toplevel = results[1]
   local gitdir = results[2]
   if not has_abs_gd then
      gitdir = uv.fs_realpath(gitdir)
   end
   local abbrev_head = process_abbrev_head(gitdir, results[3])
   return toplevel, gitdir, abbrev_head
end

local function write_to_file(path, text)
   local f = io.open(path, 'wb')
   for _, l in ipairs(text) do
      f:write(l)
      f:write('\n')
   end
   f:close()
end

M.run_diff = function(
   staged,
   text,
   diff_algo)

   local results = {}

   local buffile = os.tmpname() .. '_buf'
   write_to_file(buffile, text)

















   command({
      '-c', 'core.safecrlf=false',
      'diff',
      '--color=never',
      '--diff-algorithm=' .. diff_algo,
      '--patch-with-raw',
      '--unified=0',
      staged,
      buffile,
   }, {
      on_stdout = function(_, line)
         if startswith(line, '@@') then
            table.insert(results, gs_hunks.parse_diff_line(line))
         elseif #results > 0 then
            table.insert(results[#results].lines, line)
         end
      end,
   })
   os.remove(buffile)
   return results
end

M.set_version = function(version)
   if version ~= 'auto' then
      M.version = parse_version(version)
      return
   end
   local results = command({ '--version' })
   local line = results[1]
   assert(startswith(line, 'git version'), 'Unexpected output: ' .. line)
   local parts = vim.split(line, '%s+')
   M.version = parse_version(parts[3])
end






Obj.command = function(self, args, spec)
   spec = spec or {}
   spec.cwd = self.toplevel
   return command({ '--git-dir=' .. self.gitdir, unpack(args) }, spec)
end

Obj.update_abbrev_head = function(self)
   _, _, self.abbrev_head = get_repo_info(self.toplevel)
end

Obj.update_file_info = function(self)
   local old_object_name = self.object_name
   _, self.object_name, self.mode_bits, self.has_conflicts = self:file_info()

   return old_object_name ~= self.object_name
end

Obj.file_info = function(self, file)
   local results = self:command({
      'ls-files',
      '--stage',
      '--others',
      '--exclude-standard',
      file or self.file,
   })

   local relpath
   local object_name
   local mode_bits
   local stage
   local has_conflict = false
   for _, line in ipairs(results) do
      local parts = vim.split(line, '\t')
      if #parts > 1 then
         relpath = parts[2]
         local attrs = vim.split(parts[1], '%s+')
         stage = tonumber(attrs[3])
         if stage <= 1 then
            mode_bits = attrs[1]
            object_name = attrs[2]
         else
            has_conflict = true
         end
      else
         relpath = parts[1]
      end
   end
   return relpath, object_name, mode_bits, has_conflict
end

Obj.unstage_file = function(self)
   self:command({ 'reset', self.file })
end


Obj.get_show_text = function(self, object)
   return self:command({ 'show', object }, {
      supress_stderr = true,
   })
end


Obj.get_show = function(self, object, output_file)


   local outf = io.open(output_file, 'wb')
   self:command({ 'show', object }, {
      supress_stderr = true,
      on_stdout = function(_, line)
         outf:write(line)
         outf:write('\n')
      end,
   })
   outf:close()
end

Obj.run_blame = function(self, lines, lnum)
   local results = self:command({
      'blame',
      '--contents', '-',
      '-L', lnum .. ',+1',
      '--line-porcelain',
      self.file,
   }, {
      writer = lines,
   })
   if #results == 0 then
      return {}
   end
   local header = vim.split(table.remove(results, 1), ' ')

   local ret = {}
   ret.sha = header[1]
   ret.orig_lnum = tonumber(header[2])
   ret.final_lnum = tonumber(header[3])
   ret.abbrev_sha = string.sub(ret.sha, 1, 8)
   for _, l in ipairs(results) do
      if not startswith(l, '\t') then
         local cols = vim.split(l, ' ')
         local key = table.remove(cols, 1):gsub('-', '_')
         ret[key] = table.concat(cols, ' ')
      end
   end
   return ret
end

Obj.ensure_file_in_index = function(self)
   if not self.object_name or self.has_conflicts then
      if not self.object_name then

         self:command({ 'add', '--intent-to-add', self.file })
      else


         local info = table.concat({ self.mode_bits, self.object_name, self.relpath }, ',')
         self:command({ 'update-index', '--add', '--cacheinfo', info })
      end


      _, self.object_name, self.mode_bits, self.has_conflicts = self:file_info()
   end
end

Obj.stage_hunks = function(self, hunks, invert)
   self:ensure_file_in_index()
   self:command({
      'apply', '--whitespace=nowarn', '--cached', '--unidiff-zero', '-',
   }, {
      writer = gs_hunks.create_patch(self.relpath, hunks, self.mode_bits, invert),
   })
end

Obj.has_moved = function(self)
   local out = self:command({ 'diff', '--name-status', '-C', '--cached' })
   local orig_relpath = self.orig_relpath or self.relpath
   for _, l in ipairs(out) do
      local parts = vim.split(l, '%s+')
      if #parts == 3 then
         local orig, new = parts[2], parts[3]
         if orig_relpath == orig then
            self.orig_relpath = orig_relpath
            self.relpath = new
            self.file = self.toplevel .. '/' .. new
            return new
         end
      end
   end
end

Obj.new = function(file)
   local self = setmetatable({}, { __index = Obj })

   self.file = file
   self.username = command({ 'config', 'user.name' })[1]
   self.toplevel, self.gitdir, self.abbrev_head = 
   get_repo_info(util.dirname(file))


   if M.enable_yadm and not self.gitdir then
      if vim.startswith(file, os.getenv('HOME')) and
         #command({ 'ls-files', file }, { command = 'yadm' }) ~= 0 then
         self.toplevel, self.gitdir, self.abbrev_head = 
         get_repo_info(util.dirname(file), 'yadm')
      end
   end

   if not self.gitdir then
      return self
   end

   self.relpath, self.object_name, self.mode_bits, self.has_conflicts = 
   self:file_info()

   return self
end

return M
