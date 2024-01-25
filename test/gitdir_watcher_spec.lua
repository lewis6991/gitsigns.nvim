local helpers = require('test.gs_helpers')

local clear = helpers.clear
local exec_lua = helpers.exec_lua
local edit = helpers.edit
local eq = helpers.eq
local setup_test_repo = helpers.setup_test_repo
local cleanup = helpers.cleanup
local command = helpers.api.nvim_command
local test_config = helpers.test_config
local match_debug_messages = helpers.match_debug_messages
local match_dag = helpers.match_dag
local n, p, np = helpers.n, helpers.p, helpers.np
local setup_gitsigns = helpers.setup_gitsigns
local test_file = helpers.test_file
local git = helpers.git

helpers.env()

local function get_bufs()
  local bufs = {} --- @type table<integer,string>
  for _, b in ipairs(helpers.api.nvim_list_bufs()) do
    bufs[b] = helpers.api.nvim_buf_get_name(b)
  end
  return bufs
end

describe('gitdir_watcher', function()
  before_each(function()
    clear()

    -- Make gitisigns available
    exec_lua('package.path = ...', package.path)
    command('cd ' .. helpers.fn.system({ 'dirname', os.tmpname() }))
  end)

  after_each(function()
    cleanup()
  end)

  it('can follow moved files', function()
    setup_test_repo()
    setup_gitsigns(test_config)
    command('Gitsigns clear_debug')
    edit(test_file)

    match_debug_messages({
      'attach(1): Attaching (trigger=BufReadPost)',
      np('run_job: git .* config user.name'),
      np(
        'run_job: git .* rev%-parse %-%-show%-toplevel %-%-absolute%-git%-dir %-%-abbrev%-ref HEAD'
      ),
      np('run_job: git .* ls%-files .* ' .. vim.pesc(test_file)),
      n('watch_gitdir(1): Watching git dir'),
      np('run_job: git .* show :0:dummy.txt'),
      n('update(1): updates: 1, jobs: 5'),
    })

    eq({ [1] = test_file }, get_bufs())

    command('Gitsigns clear_debug')

    local test_file2 = test_file .. '2'
    git({ 'mv', test_file, test_file2 })

    match_dag({
      "watcher_cb(1): Git dir update: 'index.lock' { rename = true } (ignoring)",
      "watcher_cb(1): Git dir update: 'index' { rename = true }",
      "watcher_cb(1): Git dir update: 'index' { rename = true }",
    })

    match_debug_messages({
      np(
        'run_job: git .* rev%-parse %-%-show%-toplevel %-%-absolute%-git%-dir %-%-abbrev%-ref HEAD'
      ),
      np('run_job: git .* ls%-files .* ' .. vim.pesc(test_file)),
      np('run_job: git .* diff %-%-name%-status %-C %-%-cached'),
      n('handle_moved(1): File moved to dummy.txt2'),
      np('run_job: git .* ls%-files .* ' .. vim.pesc(test_file2)),
      np('handle_moved%(1%): Renamed buffer 1 from .*/dummy.txt to .*/dummy.txt2'),
      np('run_job: git .* show :0:dummy.txt2'),
      n('update(1): updates: 2, jobs: 10'),
    })

    eq({ [1] = test_file2 }, get_bufs())

    command('Gitsigns clear_debug')

    local test_file3 = test_file .. '3'

    git({ 'mv', test_file2, test_file3 })

    match_dag({
      "watcher_cb(1): Git dir update: 'index.lock' { rename = true } (ignoring)",
      "watcher_cb(1): Git dir update: 'index' { rename = true }",
      "watcher_cb(1): Git dir update: 'index' { rename = true }",
    })

    match_debug_messages({
      p(
        'run_job: git .* rev%-parse %-%-show%-toplevel %-%-absolute%-git%-dir %-%-abbrev%-ref HEAD'
      ),
      np('run_job: git .* ls%-files .* ' .. vim.pesc(test_file2)),
      np('run_job: git .* diff %-%-name%-status %-C %-%-cached'),
      n('handle_moved(1): File moved to dummy.txt3'),
      np('run_job: git .* ls%-files .* ' .. vim.pesc(test_file3)),
      np('handle_moved%(1%): Renamed buffer 1 from .*/dummy.txt2 to .*/dummy.txt3'),
      np('run_job: git .* show :0:dummy.txt3'),
      n('update(1): updates: 3, jobs: 15'),
    })

    eq({ [1] = test_file3 }, get_bufs())

    command('Gitsigns clear_debug')

    git({ 'mv', test_file3, test_file })

    match_dag({
      "watcher_cb(1): Git dir update: 'index.lock' { rename = true } (ignoring)",
      "watcher_cb(1): Git dir update: 'index' { rename = true }",
      "watcher_cb(1): Git dir update: 'index' { rename = true }",
    })

    match_debug_messages({
      p(
        'run_job: git .* rev%-parse %-%-show%-toplevel %-%-absolute%-git%-dir %-%-abbrev%-ref HEAD'
      ),
      np('run_job: git .* ls%-files .* ' .. vim.pesc(test_file3)),
      np('run_job: git .* diff %-%-name%-status %-C %-%-cached'),
      np('run_job: git .* ls%-files .* ' .. vim.pesc(test_file)),
      n('handle_moved(1): Moved file reset'),
      np('run_job: git .* ls%-files .* ' .. vim.pesc(test_file)),
      np('handle_moved%(1%): Renamed buffer 1 from .*/dummy.txt3 to .*/dummy.txt'),
      np('run_job: git .* show :0:dummy.txt'),
      n('update(1): updates: 4, jobs: 21'),
    })

    eq({ [1] = test_file }, get_bufs())
  end)
end)
