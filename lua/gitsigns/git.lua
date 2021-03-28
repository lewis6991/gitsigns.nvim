local cb_function = require('gitsigns/async').cb_function

local gsd = require("gitsigns/debug")
local util = require('gitsigns/util')
local run_job = util.run_job

local parse_diff_line = require("gitsigns/hunks").parse_diff_line
local Hunk = require('gitsigns/hunks').Hunk

local uv = vim.loop
local startswith = vim.startswith

local M = {Version = {}, }








local function parse_version(version)
   assert(version:match('%d+%.%d+%.%d+'), 'Invalid git version: ' .. version)
   local ret = {}
   local parts = vim.split(version, '%.')
   ret.major = tonumber(parts[1])
   ret.minor = tonumber(parts[2])
   ret.patch = tonumber(parts[3])
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

function M.file_info(file, toplevel)
   return function(callback)
      local relpath
      local object_name
      local mode_bits
      local stage
      local has_conflict = false
      run_job({
         command = 'git',
         args = {
            '--no-pager',
            'ls-files',
            '--stage',
            '--others',
            '--exclude-standard',
            file,
         },
         cwd = toplevel,
         on_stdout = function(_, line)
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
         end,
         on_exit = function()
            callback(relpath, object_name, mode_bits, has_conflict)
         end,
      })
   end
end

function M.get_staged(toplevel, relpath, stage, output)
   return function(callback)


      local outf = io.open(output, 'wb')
      run_job({
         command = 'git',
         args = {
            '--no-pager',
            'show',
            ':' .. tostring(stage) .. ':' .. relpath,
         },
         cwd = toplevel,
         on_stdout = function(_, line)
            outf:write(line)
            outf:write('\n')
         end,
         on_exit = function()
            outf:close()
            callback()
         end,
      })
   end
end

function M.get_staged_text(toplevel, relpath, stage)
   return function(callback)
      local result = {}
      run_job({
         command = 'git',
         args = {
            '--no-pager',
            'show',
            ':' .. tostring(stage) .. ':' .. relpath,
         },
         cwd = toplevel,
         on_stdout = function(_, line)
            table.insert(result, line)
         end,
         on_exit = function()
            callback(result)
         end,
      })
   end
end

function M.run_blame(file, toplevel, lines, lnum)
   return function(callback)
      local results = {}
      run_job({
         command = 'git',
         args = {
            '--no-pager',
            'blame',
            '--contents', '-',
            '-L', lnum .. ',+1',
            '--line-porcelain',
            file,
         },
         writer = lines,
         cwd = toplevel,
         on_stdout = function(_, line)
            table.insert(results, line)
         end,
         on_exit = function()
            local ret = {}
            local header = vim.split(table.remove(results, 1), ' ')
            ret.sha = header[1]
            ret.abbrev_sha = string.sub(ret.sha, 1, 8)
            ret.orig_lnum = header[2]
            ret.final_lnum = header[3]
            for _, l in ipairs(results) do
               if not startswith(l, '\t') then
                  local cols = vim.split(l, ' ')
                  local key = table.remove(cols, 1)
                  ret[key] = table.concat(cols, ' ')
               end
            end
            callback(ret)
         end,
      })
   end
end

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

function M.get_repo_info(path)
   return function(callback)
      local out = {}



      local has_abs_gd = check_version({ 2, 13 })
      local git_dir_opt = has_abs_gd and '--absolute-git-dir' or '--git-dir'

      run_job({
         command = 'git',
         args = { 'rev-parse',
'--show-toplevel',
git_dir_opt,
'--abbrev-ref', 'HEAD',
         },
         cwd = path,
         on_stdout = function(_, line)
            if not has_abs_gd and #out == 1 then
               line = uv.fs_realpath(line)
            end
            table.insert(out, line)
         end,
         on_exit = vim.schedule_wrap(function()
            local toplevel = out[1]
            local gitdir = out[2]
            local abbrev_head = process_abbrev_head(gitdir, out[3])
            callback(toplevel, gitdir, abbrev_head)
         end),
      })
   end
end

function M.stage_lines(toplevel, lines)
   return function(callback)
      local status = true
      local err = {}
      run_job({
         command = 'git',
         args = { 'apply', '--cached', '--unidiff-zero', '-' },
         cwd = toplevel,
         writer = lines,
         on_stderr = function(_, line)
            status = false
            table.insert(err, line)
         end,
         on_exit = function()
            if not status then
               local s = table.concat(err, '\n')
               error('Cannot stage lines. Command stderr:\n\n' .. s)
            end
            callback()
         end,
      })
   end
end

function M.add_file(toplevel, file)
   return function(callback)
      local status = true
      local err = {}
      run_job({
         command = 'git',
         args = { 'add', '--intent-to-add', file },
         cwd = toplevel,
         on_stderr = function(_, line)
            status = false
            table.insert(err, line)
         end,
         on_exit = function()
            if not status then
               local s = table.concat(err, '\n')
               error('Cannot add file. Command stderr:\n\n' .. s)
            end
            callback()
         end,
      })
   end
end

function M.update_index(toplevel, mode_bits, object_name, file)
   return function(callback)
      local status = true
      local err = {}
      local cacheinfo = table.concat({ mode_bits, object_name, file }, ',')
      run_job({
         command = 'git',
         args = { 'update-index', '--add', '--cacheinfo', cacheinfo },
         cwd = toplevel,
         on_stderr = function(_, line)
            status = false
            table.insert(err, line)
         end,
         on_exit = function()
            if not status then
               local s = table.concat(err, '\n')
               error('Cannot update index. Command stderr:\n\n' .. s)
            end
            callback()
         end,
      })
   end
end

local function write_to_file(path, text)
   local f = io.open(path, 'wb')
   for _, l in ipairs(text) do
      f:write(l)
      f:write('\n')
   end
   f:close()
end

function M.run_diff(staged, text, diff_algo)
   return function(callback)
      local results = {}

      local buffile = staged .. '_buf'
      write_to_file(buffile, text)

















      run_job({
         command = 'git',
         args = {
            '--no-pager',
            '-c', 'core.safecrlf=false',
            'diff',
            '--color=never',
            '--diff-algorithm=' .. diff_algo,
            '--patch-with-raw',
            '--unified=0',
            staged,
            buffile,
         },
         on_stdout = function(_, line)
            if startswith(line, '@@') then
               table.insert(results, parse_diff_line(line))
            else
               if #results > 0 then
                  table.insert(results[#results].lines, line)
               end
            end
         end,
         on_stderr = function(err, line)
            if err then
               gsd.eprint(err)
            end
            if line then
               gsd.eprint(line)
            end
         end,
         on_exit = function()
            os.remove(buffile)
            callback(results)
         end,
      })
   end
end

function M.set_version(version)
   return function(callback)
      if version ~= 'auto' then
         M.version = parse_version(version)
         callback()
         return
      end
      run_job({
         command = 'git', args = { '--version' },
         on_stdout = function(_, line)
            assert(startswith(line, 'git version'), 'Unexpected output: ' .. line)
            local parts = vim.split(line, '%s+')
            M.version = parse_version(parts[3])
         end,
         on_stderr = function(err, line)
            if err then
               gsd.eprint(err)
            end
            if line then
               gsd.eprint(line)
            end
         end,
         on_exit = function()
            callback()
         end,
      })
   end
end

return M
