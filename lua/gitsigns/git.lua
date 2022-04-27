local wrap = require('gitsigns.async').wrap
local scheduler = require('gitsigns.async').scheduler

local gsd = require("gitsigns.debug")
local util = require('gitsigns.util')
local subprocess = require('gitsigns.subprocess')

local gs_hunks = require("gitsigns.hunks")
local Hunk = gs_hunks.Hunk

local uv = vim.loop
local startswith = vim.startswith

local dprint = require("gitsigns.debug").dprint

local GJobSpec = {}









local M = {BlameInfo = {}, Version = {}, Repo = {}, FileProps = {}, Obj = {}, }























































































local in_git_dir = function(file)
   for _, p in ipairs(vim.split(file, util.path_sep)) do
      if p == '.git' then
         return true
      end
   end
   return false
end

local Obj = M.Obj
local Repo = M.Repo

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

local JobSpec = subprocess.JobSpec

M.command = wrap(function(args, spec, callback)
   spec = spec or {}
   spec.command = spec.command or 'git'
   spec.args = spec.command == 'git' and
   { '--no-pager', '--literal-pathspecs', unpack(args) } or args
   subprocess.run_job(spec, function(_, _, stdout, stderr)
      if not spec.supress_stderr then
         if stderr then
            gsd.eprint(stderr)
         end
      end

      local stdout_lines = vim.split(stdout or '', '\n', true)



      if stdout_lines[#stdout_lines] == '' then
         stdout_lines[#stdout_lines] = nil
      end

      if gsd.verbose then
         gsd.vprintf('%d lines:', #stdout_lines)
         for i = 1, math.min(10, #stdout_lines) do
            gsd.vprintf('\t%s', stdout_lines[i])
         end
      end

      callback(stdout_lines, stderr)
   end)
end, 3)

M.diff = function(file_cmp, file_buf, indent_heuristic, diff_algo)
   return M.command({
      '-c', 'core.safecrlf=false',
      'diff',
      '--color=never',
      '--' .. (indent_heuristic and '' or 'no-') .. 'indent-heuristic',
      '--diff-algorithm=' .. diff_algo,
      '--patch-with-raw',
      '--unified=0',
      file_cmp,
      file_buf,
   })

end

local function process_abbrev_head(gitdir, head_str, path, cmd)
   if not gitdir then
      return head_str
   end
   if head_str == 'HEAD' then
      local short_sha = M.command({ 'rev-parse', '--short', 'HEAD' }, {
         command = cmd or 'git',
         supress_stderr = true,
         cwd = path,
      })[1] or ''
      if gsd.debug_mode and short_sha ~= '' then
         short_sha = 'HEAD'
      end
      if util.path_exists(gitdir .. '/rebase-merge') or
         util.path_exists(gitdir .. '/rebase-apply') then
         return short_sha .. '(rebasing)'
      end
      return short_sha
   end
   return head_str
end

M.get_repo_info = function(path, cmd)


   local has_abs_gd = check_version({ 2, 13 })
   local git_dir_opt = has_abs_gd and '--absolute-git-dir' or '--git-dir'



   scheduler()

   local results = M.command({
      'rev-parse', '--show-toplevel', git_dir_opt, '--abbrev-ref', 'HEAD',
   }, {
      command = cmd or 'git',
      supress_stderr = true,
      cwd = path,
   })

   local toplevel = results[1]
   local gitdir = results[2]
   if gitdir and not has_abs_gd then
      gitdir = uv.fs_realpath(gitdir)
   end
   local abbrev_head = process_abbrev_head(gitdir, results[3], path, cmd)
   return toplevel, gitdir, abbrev_head
end

M.set_version = function(version)
   if version ~= 'auto' then
      M.version = parse_version(version)
      return
   end
   local results = M.command({ '--version' })
   local line = results[1]
   assert(startswith(line, 'git version'), 'Unexpected output: ' .. line)
   local parts = vim.split(line, '%s+')
   M.version = parse_version(parts[3])
end






Repo.command = function(self, args, spec)
   spec = spec or {}
   spec.cwd = self.toplevel
   return M.command({ '--git-dir=' .. self.gitdir, unpack(args) }, spec)
end

Repo.files_changed = function(self)
   local results = self:command({ 'status', '--porcelain', '--ignore-submodules' })

   local ret = {}
   for _, line in ipairs(results) do
      if line:sub(1, 2):match('^.M') then
         ret[#ret + 1] = line:sub(4, -1)
      end
   end
   return ret
end


Repo.get_show_text = function(self, object, encoding)
   local stdout, stderr = self:command({ 'show', object }, { supress_stderr = true })

   if encoding ~= 'utf-8' then
      scheduler()
      for i, l in ipairs(stdout) do

         if vim.fn.type(l) == vim.v.t_string then
            stdout[i] = vim.fn.iconv(l, encoding, 'utf-8')
         end
      end
   end

   return stdout, stderr
end

Repo.update_abbrev_head = function(self)
   _, _, self.abbrev_head = M.get_repo_info(self.toplevel)
end

Repo.new = function(dir)
   local self = setmetatable({}, { __index = Repo })

   self.username = M.command({ 'config', 'user.name' })[1]
   self.toplevel, self.gitdir, self.abbrev_head = M.get_repo_info(dir)


   if M.enable_yadm and not self.gitdir then
      if vim.startswith(dir, os.getenv('HOME')) and
         #M.command({ 'ls-files', dir }, { command = 'yadm' }) ~= 0 then
         self.toplevel, self.gitdir, self.abbrev_head = 
         M.get_repo_info(dir, 'yadm')
      end
   end

   return self
end






Obj.command = function(self, args, spec)
   return self.repo:command(args, spec)
end

Obj.update_file_info = function(self, update_relpath)
   local old_object_name = self.object_name
   local props = self:file_info()

   if update_relpath then
      self.relpath = props.relpath
   end
   self.object_name = props.object_name
   self.mode_bits = props.mode_bits
   self.has_conflicts = props.has_conflicts
   self.i_crlf = props.i_crlf
   self.w_crlf = props.w_crlf

   return old_object_name ~= self.object_name
end

Obj.file_info = function(self, file)
   local results, stderr = self:command({
      '-c', 'core.quotepath=off',
      'ls-files',
      '--stage',
      '--others',
      '--exclude-standard',
      '--eol',
      file or self.file,
   }, { supress_stderr = true })

   if stderr then


      if not stderr:match('^warning: could not open directory .*: No such file or directory') then
         gsd.eprint(stderr)
      end
   end

   local result = {}
   for _, line in ipairs(results) do
      local parts = vim.split(line, '\t')
      if #parts > 2 then
         local eol = vim.split(parts[2], '%s+')
         result.i_crlf = eol[1] == 'i/crlf'
         result.w_crlf = eol[2] == 'w/crlf'
         result.relpath = parts[3]
         local attrs = vim.split(parts[1], '%s+')
         local stage = tonumber(attrs[3])
         if stage <= 1 then
            result.mode_bits = attrs[1]
            result.object_name = attrs[2]
         else
            result.has_conflicts = true
         end
      else
         result.relpath = parts[2]
      end
   end
   return result
end

Obj.get_show_text = function(self, revision)
   if not self.relpath then
      return {}
   end

   local stdout, stderr = self.repo:get_show_text(revision .. ':' .. self.relpath, self.encoding)

   if not self.i_crlf and self.w_crlf then

      for i = 1, #stdout do
         stdout[i] = stdout[i] .. '\r'
      end
   end

   return stdout, stderr
end

Obj.unstage_file = function(self)
   self:command({ 'reset', self.file })
end

Obj.run_blame = function(self, lines, lnum, ignore_whitespace)
   if not self.object_name or self.repo.abbrev_head == '' then



      return {
         author = 'Not Committed Yet',
         ['author-mail'] = '<not.committed.yet>',
         committer = 'Not Committed Yet',
         ['committer-mail'] = '<not.committed.yet>',
      }
   end

   local args = {
      'blame',
      '--contents', '-',
      '-L', lnum .. ',+1',
      '--line-porcelain',
      self.file,
   }

   if ignore_whitespace then
      args[#args + 1] = '-w'
   end

   local ignore_file = self.repo.toplevel .. '/.git-blame-ignore-revs'
   if uv.fs_stat(ignore_file) then
      vim.list_extend(args, { '--ignore-revs-file', ignore_file })
   end

   local results = self:command(args, { writer = lines })
   if #results == 0 then
      return
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
         if key == 'previous' then
            ret.previous_sha = cols[1]
            ret.previous_filename = cols[2]
         end
      end
   end
   return ret
end

Obj.ensure_file_in_index = function(self)
   if not self.object_name or self.has_conflicts then
      if not self.object_name then

         self:command({ 'add', '--intent-to-add', self.file })
      else


         local info = string.format('%s,%s,%s', self.mode_bits, self.object_name, self.relpath)
         self:command({ 'update-index', '--add', '--cacheinfo', info })
      end

      self:update_file_info()
   end
end

Obj.stage_lines = function(self, lines)
   local stdout = self:command({
      'hash-object', '-w', '--path', self.relpath, '--stdin',
   }, { writer = lines })

   local new_object = stdout[1]

   self:command({
      'update-index', '--cacheinfo', string.format('%s,%s,%s', self.mode_bits, new_object, self.relpath),
   })
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
            self.file = self.repo.toplevel .. '/' .. new
            return new
         end
      end
   end
end

Obj.new = function(file, encoding)
   if in_git_dir(file) then
      dprint('In git dir')
      return nil
   end
   local self = setmetatable({}, { __index = Obj })

   self.file = file
   self.encoding = encoding
   self.repo = Repo.new(util.dirname(file))

   if not self.repo.gitdir then
      dprint('Not in git repo')
      return nil
   end

   self:update_file_info(true)

   return self
end

return M
