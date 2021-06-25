local helpers = require('test.gs_helpers')

local clear         = helpers.clear
local exec_lua      = helpers.exec_lua
local edit          = helpers.edit
local eq            = helpers.eq
local init          = helpers.init
local cleanup       = helpers.cleanup
local command       = helpers.command
local test_config   = helpers.test_config
local match_debug_messages = helpers.match_debug_messages
local p             = helpers.p
local setup         = helpers.setup
local test_file     = helpers.test_file
local git           = helpers.git
local get_buf_name  = helpers.curbufmeths.get_name

local it = helpers.it(it)

describe('index_watcher', function()
  before_each(function()
    clear()

    -- Make gitisigns available
    exec_lua('package.path = ...', package.path)
  end)

  after_each(function()
    cleanup()
  end)

  it('can follow moved files', function()
    init()
    setup(test_config)
    edit(test_file)

    match_debug_messages {
      "run_job: git --no-pager --version",
      'attach(1): Attaching',
      p"run_job: git .* config user.name",
      "run_job: git --no-pager rev-parse --show-toplevel --absolute-git-dir --abbrev-ref HEAD",
      p('run_job: git .* ls%-files .* '..test_file),
      'watch_index(1): Watching index',
      p'run_job: git .* show :0:dummy.txt',
      'update(1): updates: 1, jobs: 5',
    }

    command('Gitsigns clear_debug')

    git{'mv', test_file, test_file..'2'}

    match_debug_messages {
      'watcher_cb(1): Index update',
      'run_job: git --no-pager rev-parse --show-toplevel --absolute-git-dir --abbrev-ref HEAD',
      p('run_job: git .* ls%-files .* '..test_file),
      p'run_job: git .* diff %-%-name%-status %-C %-%-cached',
      'handle_moved(1): File moved to dummy.txt2',
      p('run_job: git .* ls%-files .* '..test_file..'2'),
      p'run_job: git .* show :0:dummy.txt2',
      'update(1): updates: 2, jobs: 10'
    }

    eq(test_file..'2', get_buf_name())

    command('Gitsigns clear_debug')

    git{'mv', test_file..'2', test_file..'3'}

    match_debug_messages {
      'watcher_cb(1): Index update',
      'run_job: git --no-pager rev-parse --show-toplevel --absolute-git-dir --abbrev-ref HEAD',
      p('run_job: git .* ls%-files .* '..test_file..'2'),
      p'run_job: git .* diff %-%-name%-status %-C %-%-cached',
      'handle_moved(1): File moved to dummy.txt3',
      p('run_job: git .* ls%-files .* '..test_file..'3'),
      p'run_job: git .* show :0:dummy.txt3',
      'update(1): updates: 3, jobs: 15'
    }

    eq(test_file..'3', get_buf_name())

    command('Gitsigns clear_debug')

    git{'mv', test_file..'3', test_file}

    match_debug_messages {
      'watcher_cb(1): Index update',
      'run_job: git --no-pager rev-parse --show-toplevel --absolute-git-dir --abbrev-ref HEAD',
      p('run_job: git .* ls%-files .* '..test_file..'3'),
      p'run_job: git .* diff %-%-name%-status %-C %-%-cached',
      p('run_job: git .* ls%-files .* '..test_file),
      'handle_moved(1): Moved file reset',
      p('run_job: git .* ls%-files .* '..test_file),
      p'run_job: git .* show :0:dummy.txt',
      'update(1): updates: 4, jobs: 21'
    }

    eq(test_file, get_buf_name())

  end)

end)
