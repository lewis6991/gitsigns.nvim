local api = vim.api
local uv = vim.uv or vim.loop ---@diagnostic disable-line: deprecated

--- @class gitsigns.main
local M = {}

local cwd_watcher ---@type uv.uv_fs_event_t?

local function log()
  return require('gitsigns.debug.log')
end

local function config()
  return require('gitsigns.config').config
end

local function async()
  return require('gitsigns.async')
end

--- @async
--- @return string? gitdir
--- @return string? head
local function get_gitdir_and_head()
  local cwd = uv.cwd()
  if not cwd then
    return
  end

  -- Run on the main loop to avoid:
  --   https://github.com/LazyVim/LazyVim/discussions/3407#discussioncomment-9622211
  async().schedule()

  -- Look in the cache first
  if package.loaded['gitsigns.cache'] then
    for _, bcache in pairs(require('gitsigns.cache').cache) do
      local repo = bcache.git_obj.repo
      if repo.toplevel == cwd then
        return repo.gitdir, repo.abbrev_head
      end
    end
  end

  local info = require('gitsigns.git').Repo.get_info(cwd)

  if info then
    return info.gitdir, info.abbrev_head
  end
end

---Sets up the cwd watcher to detect branch changes using uv.loop
---Uses module local variable cwd_watcher
---@async
---@param cwd string current working directory
---@param towatch string Directory to watch
local function setup_cwd_watcher(cwd, towatch)
  if cwd_watcher then
    cwd_watcher:stop()
    -- TODO(lewis6991): (#1027) Running `fs_event:stop()` -> `fs_event:start()`
    -- in the same loop event, on Windows, causes Nvim to hang on quit.
    if vim.fn.has('win32') == 1 then
      async().schedule()
    end
  else
    cwd_watcher = assert(uv.new_fs_event())
  end

  if cwd_watcher:getpath() == towatch then
    -- Already watching
    return
  end

  local debounce_trailing = require('gitsigns.debounce').debounce_trailing

  local update_head = debounce_trailing(
    100,
    --- @diagnostic disable-next-line: param-type-mismatch
    async().async(function()
      local git = require('gitsigns.git')
      local info = git.Repo.get_info(cwd) or {}
      local new_head = info.abbrev_head
      async().schedule()
      if new_head ~= vim.g.gitsigns_head then
        vim.g.gitsigns_head = new_head
        api.nvim_exec_autocmds('User', {
          pattern = 'GitSignsUpdate',
          modeline = false,
        })
      end
    end)
  )

  -- Watch .git/HEAD to detect branch changes
  cwd_watcher:start(towatch, {}, function()
    async().arun(function(err)
      local __FUNC__ = 'cwd_watcher_cb'
      if err then
        log().dprintf('Git dir update error: %s', err)
        return
      end
      log().dprint('Git cwd dir update')

      update_head()

      -- git often (always?) replaces .git/HEAD which can change the inode being
      -- watched so we need to stop the current watcher and start another one to
      -- make sure we keep getting future events
      setup_cwd_watcher(cwd, towatch)
    end)
  end)
end

--- @async
local function update_cwd_head()
  local cwd = uv.cwd()

  if not cwd then
    return
  end

  local paths = vim.fs.find('.git', {
    limit = 1,
    upward = true,
    type = 'directory',
  })

  if #paths == 0 then
    return
  end

  local gitdir, head = get_gitdir_and_head()
  async().schedule()

  api.nvim_exec_autocmds('User', {
    pattern = 'GitSignsUpdate',
    modeline = false,
  })

  vim.g.gitsigns_head = head

  if not gitdir then
    return
  end

  local towatch = gitdir .. '/HEAD'

  setup_cwd_watcher(cwd, towatch)
end

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

local function setup_attach()
  local attach_autocmd_disabled = false

  -- Need to attach in 'BufFilePost' since we always detach in 'BufFilePre'
  api.nvim_create_autocmd({ 'BufFilePost', 'BufRead', 'BufNewFile', 'BufWritePost' }, {
    group = 'gitsigns',
    desc = 'Gitsigns: attach',
    callback = function(args)
      if not config().auto_attach then
        return
      end
      local bufnr = args.buf
      if attach_autocmd_disabled then
        local __FUNC__ = 'attach_autocmd'
        log().dprint('Attaching is disabled')
        return
      end
      require('gitsigns.attach').attach(bufnr, nil, args.event)
    end,
  })

  --- vimpgrep creates and deletes lots of buffers so attaching to each one will
  --- waste lots of resource and slow down vimgrep.
  api.nvim_create_autocmd({ 'QuickFixCmdPre', 'QuickFixCmdPost' }, {
    group = 'gitsigns',
    pattern = '*vimgrep*',
    desc = 'Gitsigns: disable attach during vimgrep',
    callback = function(args)
      attach_autocmd_disabled = args.event == 'QuickFixCmdPre'
    end,
  })

  -- Attach to all open buffers
  if config().auto_attach then
    for _, buf in ipairs(api.nvim_list_bufs()) do
      if api.nvim_buf_is_loaded(buf) and api.nvim_buf_get_name(buf) ~= '' then
        -- Make sure to run each attach in its on async context in case one of the
        -- attaches is aborted.
        require('gitsigns.attach').attach(buf, nil, 'setup')
      end
    end
  end
end

local function setup_cwd_head()
  local debounce_trailing = require('gitsigns.debounce').debounce_trailing
  local update_cwd_head_debounced = debounce_trailing(100, function()
    async().arun(update_cwd_head):raise_on_error()
  end)

  update_cwd_head_debounced()

  -- Need to debounce in case some plugin changes the cwd too often
  -- (like vim-grepper)
  api.nvim_create_autocmd('DirChanged', {
    group = 'gitsigns',
    callback = function()
      update_cwd_head_debounced()
    end,
  })
end

-- When setup() is called when this is true, setup autocmads and define
-- highlights. If false then rebuild the configuration and re-setup
-- modules that depend on the configuration.
local init = true

--- Setup and start Gitsigns.
---
--- @param cfg table|nil Configuration for Gitsigns.
---     See |gitsigns-usage| for more details.
function M.setup(cfg)
  if vim.fn.executable('git') == 0 then
    print('gitsigns: git not in path. Aborting setup')
    return
  end

  if cfg then
    require('gitsigns.config').build(cfg)
  end

  -- Only do this once
  if init then
    api.nvim_create_augroup('gitsigns', {})
    setup_cli()
    -- TODO(lewis6991): do this lazily
    require('gitsigns.highlight').setup()
    setup_attach()
    setup_cwd_head()

    init = false
  end
end

--- @type gitsigns.main|gitsigns.actions|gitsigns.attach|gitsigns.debug
M = setmetatable(M, {
  __index = function(_, f)
    local attach = require('gitsigns.attach')
    if attach[f] then
      return attach[f]
    end

    local actions = require('gitsigns.actions')
    if actions[f] then
      return actions[f]
    end

    if config().debug_mode then
      local debug = require('gitsigns.debug')
      if debug[f] then
        return debug[f]
      end
    end
  end,
})

return M
