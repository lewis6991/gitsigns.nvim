local async = require('gitsigns.async')
local cache = require('gitsigns.cache').cache
local git = require('gitsigns.git')
local run_diff = require('gitsigns.diff')
local config = require('gitsigns.config').config
local util = require('gitsigns.util')

local uv = vim.uv or vim.loop ---@diagnostic disable-line: deprecated

local current_buf = vim.api.nvim_get_current_buf

--- @class gitsigns.qflist
local M = {}

--- @param buf_or_filename string|integer
--- @param hunks Gitsigns.Hunk.Hunk[]
--- @param qflist table[]
local function hunks_to_qflist(buf_or_filename, hunks, qflist)
  for i, hunk in ipairs(hunks) do
    qflist[#qflist + 1] = {
      bufnr = type(buf_or_filename) == 'number' and buf_or_filename or nil,
      filename = type(buf_or_filename) == 'string' and buf_or_filename or nil,
      lnum = hunk.added.start,
      text = string.format('Lines %d-%d (%d/%d)', hunk.added.start, hunk.vend, i, #hunks),
    }
  end
end

--- @async
--- @param target 'all'|'attached'|integer?
--- @return table[]?
local function buildqflist(target)
  target = target or current_buf()
  if target == 0 then
    target = current_buf()
  end
  local qflist = {} --- @type table[]

  if type(target) == 'number' then
    local bufnr = target
    local bcache = cache[bufnr]
    if not bcache or not bcache.hunks then
      return
    end
    hunks_to_qflist(bufnr, bcache.hunks, qflist)
  elseif target == 'attached' then
    for bufnr, bcache in pairs(cache) do
      hunks_to_qflist(bufnr, assert(bcache.hunks), qflist)
    end
  elseif target == 'all' then
    local repos = {} --- @type table<string,Gitsigns.Repo>
    for _, bcache in pairs(cache) do
      local repo = bcache.git_obj.repo
      if not repos[repo.gitdir] then
        repos[repo.gitdir] = repo
      end
    end

    local repo = git.Repo.get((assert(uv.cwd())))
    if repo and not repos[repo.gitdir] then
      repos[repo.gitdir] = repo
    end

    for _, r in pairs(repos) do
      for _, f in ipairs(r:files_changed(config.base)) do
        local f_abs = r.toplevel .. '/' .. f
        local stat = uv.fs_stat(f_abs)
        if stat and stat.type == 'file' then
          ---@type string
          local obj
          if config.base and config.base ~= ':0' then
            obj = config.base .. ':' .. f
          else
            obj = ':0:' .. f
          end
          local a = r:get_show_text(obj)
          async.schedule()
          local hunks = run_diff(a, util.file_lines(f_abs))
          hunks_to_qflist(f_abs, hunks, qflist)
        end
      end
    end
  end
  return qflist
end

--- Populate the quickfix list with hunks. Automatically opens the
--- quickfix window.
--- @async
--- @param target integer|'attached'|'all'?
--- @param opts table?
function M.setqflist(target, opts)
  opts = opts or {}
  if opts.open == nil then
    opts.open = true
  end
  --- @type vim.fn.setqflist.what
  local qfopts = {
    items = buildqflist(target),
    title = 'Hunks',
  }
  async.schedule()
  if opts.use_location_list then
    local nr = opts.nr or 0
    vim.fn.setloclist(nr, {}, ' ', qfopts)
    if opts.open then
      if config.trouble then
        require('trouble').open('loclist')
      else
        vim.cmd.lopen()
      end
    end
  else
    vim.fn.setqflist({}, ' ', qfopts)
    if opts.open then
      if config.trouble then
        require('trouble').open('quickfix')
      else
        vim.cmd.copen()
      end
    end
  end
end

return M
