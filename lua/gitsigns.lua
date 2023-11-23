local async = require('gitsigns.async')

local gs_config = require('gitsigns.config')
local config = gs_config.config

local log = require('gitsigns.debug.log')
local dprintf = log.dprintf
local dprint = log.dprint

local api = vim.api
local uv = vim.loop

local M = {}

local cwd_watcher ---@type uv.uv_fs_event_t?

local update_cwd_head = async.void(function()
  local paths = vim.fs.find('.git', {
    limit = 1,
    upward = true,
    type = 'directory',
  })

  if #paths == 0 then
    return
  end

  if cwd_watcher then
    cwd_watcher:stop()
  else
    cwd_watcher = assert(uv.new_fs_event())
  end

  local cwd = assert(vim.loop.cwd())
  --- @type string, string
  local gitdir, head

  local gs_cache = require('gitsigns.cache')

  -- Look in the cache first
  for _, bcache in pairs(gs_cache.cache) do
    local repo = bcache.git_obj.repo
    if repo.toplevel == cwd then
      head = repo.abbrev_head
      gitdir = repo.gitdir
      break
    end
  end

  local git = require('gitsigns.git')

  if not head or not gitdir then
    local info = git.get_repo_info(cwd)
    gitdir = info.gitdir
    head = info.abbrev_head
  end

  async.scheduler()
  vim.g.gitsigns_head = head

  if not gitdir then
    return
  end

  local towatch = gitdir .. '/HEAD'

  if cwd_watcher:getpath() == towatch then
    -- Already watching
    return
  end

  local debounce_trailing = require('gitsigns.debounce').debounce_trailing

  local update_head = debounce_trailing(
    100,
    async.void(function()
      local new_head = git.get_repo_info(cwd).abbrev_head
      async.scheduler()
      vim.g.gitsigns_head = new_head
    end)
  )

  -- Watch .git/HEAD to detect branch changes
  cwd_watcher:start(
    towatch,
    {},
    async.void(function(err)
      local __FUNC__ = 'cwd_watcher_cb'
      if err then
        dprintf('Git dir update error: %s', err)
        return
      end
      dprint('Git cwd dir update')

      update_head()
    end)
  )
end)

local function setup_cli()
  api.nvim_create_user_command('Gitsigns', function(params)
    require('gitsigns.cli').run(params)
  end, {
    force = true,
    nargs = '*',
    range = true,
    complete = function(arglead, line)
      return require('gitsigns.cli').complete(arglead, line)
    end,
  })
end

local function setup_debug()
  log.debug_mode = config.debug_mode
  log.verbose = config._verbose
end

--- @async
local function setup_attach()
  async.scheduler()

  api.nvim_create_autocmd({ 'BufRead', 'BufNewFile', 'BufWritePost' }, {
    group = 'gitsigns',
    callback = function(data)
      require('gitsigns.attach').attach(data.buf, nil, data.event)
    end,
  })

  -- Attach to all open buffers
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_loaded(buf) and api.nvim_buf_get_name(buf) ~= '' then
      -- Make sure to run each attach in its on async context in case one of the
      -- attaches is aborted.
      local attach = require('gitsigns.attach')
      async.run(attach.attach, buf, nil, 'setup')
    end
  end
end

--- @async
local function setup_cwd_head()
  async.scheduler()
  update_cwd_head()
  -- Need to debounce in case some plugin changes the cwd too often
  -- (like vim-grepper)
  api.nvim_create_autocmd('DirChanged', {
    group = 'gitsigns',
    callback = function()
      local debounce = require('gitsigns.debounce').debounce_trailing
      debounce(100, update_cwd_head)
    end,
  })
end

--- Setup and start Gitsigns.
---
--- Attributes: ~
---     {async}
---
--- @param cfg table|nil Configuration for Gitsigns.
---     See |gitsigns-usage| for more details.
M.setup = async.void(function(cfg)
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

  setup_debug()
  setup_cli()

  api.nvim_create_augroup('gitsigns', {})

  if config._test_mode then
    require('gitsigns.attach')._setup()
    require('gitsigns.git')._set_version(config._git_version)
  end

  setup_attach()
  setup_cwd_head()

  M._setup_done = true
end)

return setmetatable(M, {
  __index = function(_, f)
    local attach = require('gitsigns.attach')
    if attach[f] then
      return attach[f]
    end

    local actions = require('gitsigns.actions')
    if actions[f] then
      return actions[f]
    end

    if config.debug_mode then
      local debug = require('gitsigns.debug')
      if debug[f] then
        return debug[f]
      end
    end
  end,
})
