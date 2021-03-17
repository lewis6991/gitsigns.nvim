require('gitsigns/async')

local gsd = require("gitsigns/debug")
local util = require('gitsigns/util')
local run_job = util.run_job

local parse_diff_line = require("gitsigns/hunks").parse_diff_line

local M = {}

function M.file_info(file: string, toplevel: string): cb_function
  return function(callback: function(string, string, string, boolean))
    local relpath: string
    local object_name: string
    local mode_bits: string
    local stage: number
    local has_conflict: boolean = false
    run_job {
      command = 'git',
      args = {
        '--no-pager',
        'ls-files',
        '--stage',
        '--others',
        '--exclude-standard',
        file
      },
      cwd = toplevel,
      on_stdout = function(_, line: string)
        local parts = vim.split(line, '\t')
        if #parts > 1 then -- tracked file
          relpath = parts[2]
          local attrs = vim.split(parts[1], '%s+')
          stage = tonumber(attrs[3])
          if stage <= 1 then
              mode_bits   = attrs[1]
              object_name = attrs[2]
          else
              has_conflict = true
          end
        else -- untracked file
          relpath = parts[1]
        end
      end,
      on_exit = function()
        callback(relpath, object_name, mode_bits, has_conflict)
      end
    }
  end
end

function M.get_staged(toplevel: string, relpath: string, stage: number, output: string): cb_function
  return function(callback: function())
    -- On windows 'w' mode use \r\n instead of \n, see:
    -- https://stackoverflow.com/a/43967013
    local outf = io.open(output , 'wb')
    run_job {
      command = 'git',
      args = {
        '--no-pager',
        'show',
        ':'..tostring(stage)..':'..relpath,
      },
      cwd = toplevel,
      on_stdout = function(_, line: string)
        outf:write(line)
        outf:write('\n')
      end,
      on_exit = function()
        outf:close()
        callback()
      end
    }
  end
end

function M.get_staged_text(toplevel: string, relpath: string, stage: number): cb_function
  return function(callback: function({string}))
    local result = {}
    run_job {
      command = 'git',
      args = {
        '--no-pager',
        'show',
        ':'..tostring(stage)..':'..relpath,
      },
      cwd = toplevel,
      on_stdout = function(_, line: string)
        table.insert(result, line)
      end,
      on_exit = function()
        callback(result)
      end
    }
  end
end

function M.run_blame(file: string, toplevel: string, lines: {string}, lnum: number): cb_function
  return function(callback: function({string:string}))
    local results: {string} = {}
    run_job {
      command = 'git',
      args = {
        '--no-pager',
        'blame',
        '--contents', '-',
        '-L', lnum..',+1',
        '--line-porcelain',
        file
      },
      writer = lines,
      cwd = toplevel,
      on_stdout = function(_, line: string)
        table.insert(results, line)
      end,
      on_exit = function()
        local ret: {string:string} = {}
        local header = vim.split(table.remove(results, 1), ' ')
        ret.sha = header[1]
        ret.abbrev_sha = string.sub(ret.sha, 1, 8)
        ret.orig_lnum = header[2]
        ret.final_lnum = header[3]
        for _, l in ipairs(results) do
          if not vim.startswith(l, '\t') then
            local cols = vim.split(l, ' ')
            local key = table.remove(cols, 1)
            ret[key] = table.concat(cols, ' ')
          end
        end
        callback(ret)
      end
    }
  end
end

local function process_abbrev_head(gitdir: string, head_str: string): string
  if not gitdir then
    return head_str
  end
  if head_str == 'HEAD' then
    if util.path_exists(gitdir..'/rebase-merge')
      or util.path_exists(gitdir..'/rebase-apply') then
      return '(rebasing)'
    elseif gsd.debug_mode then
      return head_str
    else
      return ''
    end
  end
  return head_str
end

function M.get_repo_info(path: string): cb_function
  return function(callback: function)
    local out = {}
    run_job {
      command = 'git',
      args = {'rev-parse',
        '--show-toplevel',
        '--absolute-git-dir',
        '--abbrev-ref', 'HEAD',
      },
      cwd = path,
      on_stdout = function(_, line: string)
        table.insert(out, line)
      end,
      on_exit = vim.schedule_wrap(function()
        local toplevel = out[1]
        local gitdir = out[2]
        local abbrev_head = process_abbrev_head(gitdir, out[3])
        callback(toplevel, gitdir, abbrev_head)
      end)
    }
  end
end

function M.stage_lines(toplevel: string, lines: {string}): cb_function
  return function(callback: function())
    local status = true
    local err = {}
    run_job {
      command = 'git',
      args = {'apply', '--cached', '--unidiff-zero', '-'},
      cwd = toplevel,
      writer = lines,
      on_stderr = function(_, line: string)
        status = false
        table.insert(err, line)
      end,
      on_exit = function()
        if not status then
          local s = table.concat(err, '\n')
          error('Cannot stage lines. Command stderr:\n\n'..s)
        end
        callback()
      end
    }
  end
end

function M.add_file(toplevel: string, file: string): cb_function
  return function(callback: function())
    local status = true
    local err = {}
    run_job {
      command = 'git',
      args = {'add', '--intent-to-add', file},
      cwd = toplevel,
      on_stderr = function(_, line: string)
        status = false
        table.insert(err, line)
      end,
      on_exit = function()
        if not status then
          local s = table.concat(err, '\n')
          error('Cannot add file. Command stderr:\n\n'..s)
        end
        callback()
      end
    }
  end
end

function M.update_index(toplevel: string, mode_bits: string, object_name: string, file: string): cb_function
  return function(callback: function())
    local status = true
    local err = {}
    local cacheinfo = table.concat({mode_bits, object_name, file}, ',')
    run_job {
      command = 'git',
      args = {'update-index', '--add', '--cacheinfo', cacheinfo},
      cwd = toplevel,
      on_stderr = function(_, line: string)
        status = false
        table.insert(err, line)
      end,
      on_exit = function()
        if not status then
          local s = table.concat(err, '\n')
          error('Cannot update index. Command stderr:\n\n'..s)
        end
        callback()
      end
    }
  end
end

local function write_to_file(path: string, text: {string})
  local f = io.open(path, 'wb')
  for _, l in ipairs(text) do
    f:write(l)
    f:write('\n')
  end
  f:close()
end

function M.run_diff(staged: string, text: {string}, diff_algo: string): cb_function
  return function(callback: function)
    local results: {Hunk} = {}

    local buffile = staged..'_buf'
    write_to_file(buffile, text)

    -- Taken from gitgutter, diff.vim:
    --
    -- If a file has CRLF line endings and git's core.autocrlf is true, the file
    -- in git's object store will have LF line endings. Writing it out via
    -- git-show will produce a file with LF line endings.
    --
    -- If this last file is one of the files passed to git-diff, git-diff will
    -- convert its line endings to CRLF before diffing -- which is what we want
    -- but also by default outputs a warning on stderr.
    --
    --   warning: LF will be replace by CRLF in <temp file>.
    --   The file will have its original line endings in your working directory.
    --
    -- We can safely ignore the warning, we turn it off by passing the '-c
    -- "core.safecrlf=false"' argument to git-diff.

    run_job {
      command = 'git',
      args = {
        '--no-pager',
        '-c', 'core.safecrlf=false',
        'diff',
        '--color=never',
        '--diff-algorithm='..diff_algo,
        '--patch-with-raw',
        '--unified=0',
        staged,
        buffile,
      },
      on_stdout = function(_, line: string)
        if vim.startswith(line, '@@') then
          table.insert(results, parse_diff_line(line))
        else
          if #results > 0 then
            table.insert(results[#results].lines, line)
          end
        end
      end,
      on_stderr = function(err: string, line: string)
        if err then
           -- On windows print() crashes in callback threads
           vim.schedule(function()
              print('error: ' .. err, 'NA', 'run_diff')
           end)
        elseif line then
           -- On windows print() crashes in callback threads
           vim.schedule(function()
              print('error: ' .. line, 'NA', 'run_diff')
           end)
         end
      end,
      on_exit = function()
        os.remove(buffile)
        callback(results)
      end
    }
  end
end

return M
