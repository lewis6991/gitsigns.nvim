local Job = require('plenary.job')

local gsd = require("gitsigns.debug")

local record M
  path_sep: string
  is_unix: boolean
  job_cnt: integer
end

M.job_cnt = 0

function M.path_exists(path: string): boolean
  return vim.loop.fs_stat(path) and true or false
end

function M.run_job(job_spec: Job.JobSpec)
  if gsd.debug_mode then
    local cmd: string = job_spec.command..' '..table.concat(job_spec.args, ' ')
    gsd.dprint(cmd)
  end
  Job:new(job_spec):start()
  M.job_cnt = M.job_cnt + 1
end

function M.get_jit_os(): string
  if jit then
    return jit.os:lower()
  end
  return
end

local jit_os: string

if jit then
  jit_os = jit.os:lower()
end

M.is_unix = (function(): boolean
  if jit_os == 'linux' or jit_os == 'osx' then
    return true
  end
  return false
end)()

function M.dirname(file: string): string
  return file:match(string.format('^(.+)%s[^%s]+', M.path_sep, M.path_sep))
end

function M.file_lines(file: string): {string}
  local text: {string} = {}
  for line in io.lines(file) do
    text[#text+1] = line
  end
  return text
end

M.path_sep = (function(): string
  if jit_os then
    if M.is_unix then
      return '/'
    end
    return '\\'
  end
  return package.config:sub(1, 1)
end)()

function M.tmpname(): string
  if M.is_unix then
    return os.tmpname()
  end
  return vim.fn.tempname()
end

return M
