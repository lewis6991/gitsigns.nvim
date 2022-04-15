local helpers = require('test.gs_helpers')

local clear           = helpers.clear
local exec_lua        = helpers.exec_lua
local edit            = helpers.edit
local eq              = helpers.eq
local setup_test_repo = helpers.setup_test_repo
local cleanup         = helpers.cleanup
local command         = helpers.command
local test_config     = helpers.test_config
local match_debug_messages = helpers.match_debug_messages
local p               = helpers.p
local setup_gitsigns  = helpers.setup_gitsigns
local test_file       = helpers.test_file
local git             = helpers.git
local get_buf_name    = helpers.curbufmeths.get_name

local it = helpers.it(it)

describe('gitdir_watcher', function()
  before_each(function()
    clear()

    -- Make gitisigns available
    exec_lua('package.path = ...', package.path)
    command('cd '..helpers.funcs.system{"dirname", os.tmpname()})
  end)

  after_each(function()
    cleanup()
  end)

  it('can follow moved files', function()
    setup_test_repo()
    setup_gitsigns(test_config)
    command('Gitsigns clear_debug')
    edit(test_file)

    match_debug_messages {
      'attach(1): Attaching (trigger=BufRead)',
      p"run_job: git .* config user.name",
      p"run_job: git .* rev%-parse %-%-show%-toplevel %-%-absolute%-git%-dir %-%-abbrev%-ref HEAD",
      p('run_job: git .* ls%-files .* '..test_file),
      'watch_gitdir(1): Watching git dir',
      p'run_job: git .* show :0:dummy.txt',
      'update(1): updates: 1, jobs: 6',
    }

    command('Gitsigns clear_debug')

    git{'mv', test_file, test_file..'2'}

    match_debug_messages {
      'watcher_cb(1): Git dir update',
      p'run_job: git .* rev%-parse %-%-show%-toplevel %-%-absolute%-git%-dir %-%-abbrev%-ref HEAD',
      p('run_job: git .* ls%-files .* '..test_file),
      p'run_job: git .* diff %-%-name%-status %-C %-%-cached',
      'handle_moved(1): File moved to dummy.txt2',
      p('run_job: git .* ls%-files .* '..test_file..'2'),
      p'run_job: git .* show :0:dummy.txt2',
      'update(1): updates: 2, jobs: 11'
    }

    eq(test_file..'2', get_buf_name())

    command('Gitsigns clear_debug')

    git{'mv', test_file..'2', test_file..'3'}

    match_debug_messages {
      'watcher_cb(1): Git dir update',
      p'run_job: git .* rev%-parse %-%-show%-toplevel %-%-absolute%-git%-dir %-%-abbrev%-ref HEAD',
      p('run_job: git .* ls%-files .* '..test_file..'2'),
      p'run_job: git .* diff %-%-name%-status %-C %-%-cached',
      'handle_moved(1): File moved to dummy.txt3',
      p('run_job: git .* ls%-files .* '..test_file..'3'),
      p'run_job: git .* show :0:dummy.txt3',
      'update(1): updates: 3, jobs: 16'
    }

    eq(test_file..'3', get_buf_name())

    command('Gitsigns clear_debug')

    git{'mv', test_file..'3', test_file}

    match_debug_messages {
      'watcher_cb(1): Git dir update',
      p'run_job: git .* rev%-parse %-%-show%-toplevel %-%-absolute%-git%-dir %-%-abbrev%-ref HEAD',
      p('run_job: git .* ls%-files .* '..test_file..'3'),
      p'run_job: git .* diff %-%-name%-status %-C %-%-cached',
      p('run_job: git .* ls%-files .* '..test_file),
      'handle_moved(1): Moved file reset',
      p('run_job: git .* ls%-files .* '..test_file),
      p'run_job: git .* show :0:dummy.txt',
      'update(1): updates: 4, jobs: 22'
    }

    eq(test_file, get_buf_name())

  end)

end)
