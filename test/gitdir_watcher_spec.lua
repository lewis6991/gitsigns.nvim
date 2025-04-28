local helpers = require('test.gs_helpers')

local clear = helpers.clear
local system = helpers.fn.system
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
    command('cd ' .. system({ 'dirname', os.tmpname() }))
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
      np(
        'run_job: git .* rev%-parse %-%-show%-toplevel %-%-absolute%-git%-dir %-%-abbrev%-ref HEAD'
      ),
      np('run_job: git .* config user.name'),
      np('run_job: git .* ls%-files .* ' .. vim.pesc(test_file)),
      n('watch_gitdir(1): Watching git dir'),
      np('run_job: git .* show .*'),
    })

    eq({ [1] = test_file }, get_bufs())

    command('Gitsigns clear_debug')

    local test_file2 = test_file .. '2'
    git('mv', test_file, test_file2)

    match_dag({
      "watcher_cb(1): Git dir update: 'index.lock' { rename = true }",
      "watcher_cb(1): Git dir update: 'index' { rename = true }",
      "watcher_cb(1): Git dir update: 'index' { rename = true }",
    })

    match_debug_messages({
      np(
        'run_job: git .* rev%-parse %-%-show%-toplevel %-%-absolute%-git%-dir %-%-abbrev%-ref HEAD'
      ),
      np('run_job: git .* ls%-files .* ' .. vim.pesc(test_file)),
      np('run_job: git .* diff %-%-name%-status .* %-%-cached'),
      n('handle_moved(1): File moved to dummy.txt2'),
      np('run_job: git .* ls%-files .* ' .. vim.pesc(test_file2)),
      np('handle_moved%(1%): Renamed buffer 1 from .*/dummy.txt to .*/dummy.txt2'),
      np('run_job: git .* show .*'),
    })

    eq({ [1] = test_file2 }, get_bufs())

    command('Gitsigns clear_debug')

    local test_file3 = test_file .. '3'

    git('mv', test_file2, test_file3)

    match_dag({
      "watcher_cb(1): Git dir update: 'index.lock' { rename = true }",
      "watcher_cb(1): Git dir update: 'index' { rename = true }",
      "watcher_cb(1): Git dir update: 'index' { rename = true }",
    })

    match_debug_messages({
      p(
        'run_job: git .* rev%-parse %-%-show%-toplevel %-%-absolute%-git%-dir %-%-abbrev%-ref HEAD'
      ),
      np('run_job: git .* ls%-files .* ' .. vim.pesc(test_file2)),
      np('run_job: git .* diff %-%-name%-status .* %-%-cached'),
      n('handle_moved(1): File moved to dummy.txt3'),
      np('run_job: git .* ls%-files .* ' .. vim.pesc(test_file3)),
      np('handle_moved%(1%): Renamed buffer 1 from .*/dummy.txt2 to .*/dummy.txt3'),
      np('run_job: git .* show .*'),
    })

    eq({ [1] = test_file3 }, get_bufs())

    command('Gitsigns clear_debug')

    git('mv', test_file3, test_file)

    match_dag({
      "watcher_cb(1): Git dir update: 'index.lock' { rename = true }",
      "watcher_cb(1): Git dir update: 'index' { rename = true }",
      "watcher_cb(1): Git dir update: 'index' { rename = true }",
    })

    match_debug_messages({
      p(
        'run_job: git .* rev%-parse %-%-show%-toplevel %-%-absolute%-git%-dir %-%-abbrev%-ref HEAD'
      ),
      np('run_job: git .* ls%-files .* ' .. vim.pesc(test_file3)),
      np('run_job: git .* diff %-%-name%-status .* %-%-cached'),
      np('run_job: git .* ls%-files .* ' .. vim.pesc(test_file)),
      n('handle_moved(1): Moved file reset'),
      np('run_job: git .* ls%-files .* ' .. vim.pesc(test_file)),
      np('handle_moved%(1%): Renamed buffer 1 from .*/dummy.txt3 to .*/dummy.txt'),
      np('run_job: git .* show .*'),
    })

    eq({ [1] = test_file }, get_bufs())
  end)

  it('can debounce and throttle updates per buffer', function()
    helpers.git_init_scratch()

    local f1 = vim.fs.joinpath(helpers.scratch, 'file1')
    local f2 = vim.fs.joinpath(helpers.scratch, 'file2')

    helpers.write_to_file(f1, { '1', '2', '3' })
    helpers.write_to_file(f2, { '1', '2', '3' })

    git('add', f1, f2)
    git('commit', '-m', 'init commit')

    setup_gitsigns(test_config)

    command('edit ' .. f1)
    helpers.feed('Aa<esc>')
    command('write')
    local b1 = helpers.api.nvim_get_current_buf()

    command('split ' .. f2)
    helpers.feed('Ab<esc>')
    command('write')
    local b2 = helpers.api.nvim_get_current_buf()

    helpers.check({ signs = { changed = 1 } }, b1)
    helpers.check({ signs = { changed = 1 } }, b2)

    git('add', f1, f2)

    helpers.check({ signs = {} }, b1)
    helpers.check({ signs = {} }, b2)
  end)
end)
