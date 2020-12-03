local Job = require('plenary/job')
local Path = require('plenary/path')

local pln_cm = require('plenary/context_manager')
local with = pln_cm.with
local open = pln_cm.open

local gs_async = require('gitsigns/async')
local async      = gs_async.async
local async0     = gs_async.async0
local await      = gs_async.await
local await_main = gs_async.await_main

local gs_debounce = require('gitsigns/debounce')
local throttle_leading  = gs_debounce.throttle_leading
local debounce_trailing = gs_debounce.debounce_trailing

local gs_popup    = require('gitsigns/popup')

local sign_define    = require('gitsigns/signs').sign_define
local apply_config   = require('gitsigns/config')
local mk_repeatable  = require('gitsigns/repeat').mk_repeatable
local apply_mappings = require('gitsigns/mappings')

local gs_hunks = require("gitsigns/hunks")
local create_patch    = gs_hunks.create_patch
local process_hunks   = gs_hunks.process_hunks
local parse_diff_line = gs_hunks.parse_diff_line
local get_summary     = gs_hunks.get_summary
local find_hunk       = gs_hunks.find_hunk

local gs_objs = require("gitsigns/objects")
local validate = gs_objs.validate

local api = vim.api
local current_buf = api.nvim_get_current_buf

local config = {}

local sign_map = {
  add          = "GitSignsAdd",
  delete       = "GitSignsDelete",
  change       = "GitSignsChange",
  topdelete    = "GitSignsTopDelete",
  changedelete = "GitSignsChangeDelete",
}

local function dprint(...)
  if config.debug_mode then
    require('gitsigns/debug').dprint(...)
  end
end

local function dirname(file)
  return file:match("(.*/)")
end

local function set_buf_var(bufnr, name, value)
  vim.schedule(function()
    api.nvim_buf_set_var(bufnr, name, value)
  end)
end

local function write_to_file(file, content)
  with(open(file, 'w'), function(writer)
    for _, l in pairs(content) do
      writer:write(l..'\n')
    end
  end)
end

local path_exists = function(p)
  return Path:new(p):exists()
end

local job_cnt = 0

local function run_job(job_spec)
  if config.debug_mode then
    local cmd = job_spec.command..' '..table.concat(job_spec.args, ' ')
    dprint('Running: '..cmd)
  end
  Job:new(job_spec):start()
  job_cnt = job_cnt + 1
end

local function git_relative(file, toplevel, callback)
  local relpath
  local object_name
  local mode_bits
  run_job {
    command = 'git',
    args = {'--no-pager', 'ls-files', '--stage', file},
    cwd = toplevel,
    on_stdout = function(_, line)
      local parts = vim.split(line, ' +')
      mode_bits   = parts[1]
      object_name = parts[2]
      relpath = vim.split(parts[3], '\t', true)[2]
    end,
    on_exit = function(_, code)
      callback(relpath, object_name, mode_bits)
    end
  }
end

local get_staged_txt = function(toplevel, relpath, callback)
  local content = {}
  run_job {
    command = 'git',
    args = {'--no-pager', 'show', ':'..relpath},
    cwd = toplevel,
    on_stdout = function(_, line)
      table.insert(content, line)
    end,
    on_exit = function(_, code)
      callback(code == 0 and content or nil)
    end
  }
end

local run_diff = function(staged, text, callback)
  local results = {}
  run_job {
    command = 'git',
    args = {
      '--no-pager',
      'diff',
      '--color=never',
      '--diff-algorithm='..config.diff_algorithm,
      '--patch-with-raw',
      '--unified=0',
      staged,
      '-'
    },
    writer = text,
    on_stdout = function(_, line)
      if vim.startswith(line, '@@') then
        table.insert(results, parse_diff_line(line))
      else
        if #results > 0 then
          table.insert(results[#results].lines, line)
        end
      end
    end,
    on_stderr = function(_, line)
      print('error: '..line, 'NA', 'run_diff')
    end,
    on_exit = function()
      callback(results)
    end
  }
end

local cache = {}

local function get_cache(bufnr)
  local c = cache[bufnr]
  validate.cache_entry(c)
  return c
end

local function get_cache_opt(bufnr)
  local c = cache[bufnr]
  validate.cache_entry_opt(c)
  return c
end

local function get_hunk(bufnr, hunks)
  bufnr = bufnr or current_buf()
  hunks = hunks or cache[bufnr].hunks

  validate.hunks(hunks)

  local lnum = api.nvim_win_get_cursor(0)[1]
  return find_hunk(lnum, hunks)
end

local function process_abbrev_head(gitdir, head_str)
  if not gitdir then
    return head_str
  end
  if head_str == 'HEAD' then
    if path_exists(gitdir..'/rebase-merge')
      or path_exists(gitdir..'/rebase-apply') then
      return '(rebasing)'
    else
      return ''
    end
  end
  return head_str
end

local get_repo_info = function(file, callback)
  local out = {}
  run_job {
    command = 'git',
    args = {'rev-parse',
      '--show-toplevel',
      '--absolute-git-dir',
      '--abbrev-ref', 'HEAD',
    },
    cwd = dirname(file),
    on_stdout = function(_, line)
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

local add_signs = function(bufnr, signs, reset)
  validate.signs(signs)

  reset = reset or false

  if reset then
    vim.fn.sign_unplace('gitsigns_ns', {buffer = bufnr})
  end

  for _, s in pairs(signs) do
    local type = sign_map[s.type]
    local count = s.count

    local cs = config.signs[s.type]
    if cs.show_count and count then
      local cc = config.count_chars
      local count_suffix = cc[count] and count or cc['+'] and 'Plus' or ''
      local count_char   = cc[count]           or cc['+']            or ''
      type = type..count_suffix
      sign_define(type, cs.hl, cs.text..count_char)
    end

    vim.fn.sign_place(s.lnum, 'gitsigns_ns', type, bufnr, {
      lnum = s.lnum, priority = config.sign_priority
    })
  end
end

local get_staged = async('get_staged', function(bufnr, staged_path, toplevel, relpath)
  vim.validate {
    bufnr       = {bufnr      , 'number'},
    staged_path = {staged_path, 'string'},
    toplevel    = {toplevel   , 'string'},
    relpath     = {relpath    , 'string'}
  }

  await_main()
  local staged_txt = await(get_staged_txt, toplevel, relpath)

  if not staged_txt then
    dprint('File not in index', bufnr, 'get_staged')
    return false
  end

  await_main()

  write_to_file(staged_path, staged_txt)
  dprint('Updated staged file', bufnr, 'get_staged')
  return true
end)

local update_cnt = 0

local update = debounce_trailing(100, async('update', function(bufnr)
  vim.validate {bufnr = {bufnr, 'number'}}

  local bcache = get_cache_opt(bufnr)
  if not bcache then
    error('Cache for buffer '..bufnr..' was nil')
    return
  end

  local file, relpath, toplevel, staged =
      bcache.file, bcache.relpath, bcache.toplevel, bcache.staged

  if not path_exists(staged) then
    local res = await(get_staged, bufnr, staged, toplevel, relpath)
    if not res then
      return
    end
  end

  await_main()

  local buftext = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  bcache.hunks = await(run_diff, staged, buftext)

  local status = get_summary(bcache.hunks)
  status.head = bcache.abbrev_head

  local signs = process_hunks(bcache.hunks)

  await_main()

  add_signs(bufnr, signs, true)

  set_buf_var(bufnr, 'gitsigns_status_dict', status)
  set_buf_var(bufnr, 'gitsigns_status', config.status_formatter(status))

  update_cnt = update_cnt + 1
  dprint(string.format('updates: %s, jobs: %s', update_cnt, job_cnt), bufnr, 'update')
end))

local watch_index = async('watch_index', function(bufnr, gitdir, on_change)
  vim.validate {
    bufnr     = {bufnr    , 'number'},
    gitdir    = {gitdir   , 'string'},
    on_change = {on_change, 'function'}
  }

  local index = gitdir..'/index'
  if not path_exists(index) then
    error('Cannot find index file: '..index)
    return
  end

  -- TODO: Buffers of the same git repo can share an index watcher
  dprint('Watching index', bufnr, 'watch_index')

  local w = vim.loop.new_fs_poll()
  w:start(index, config.watch_index.interval, on_change)

  return w
end)

local stage_lines = function(toplevel, lines, callback)
  local status = true
  local err = {}
  run_job {
    command = 'git',
    args = {'apply', '--cached', '--unidiff-zero', '-'},
    cwd = toplevel,
    writer = lines,
    on_stderr = function(_, line)
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

local stage_hunk = async('stage_hunk', function()
  local bufnr = current_buf()

  local bcache = get_cache_opt(bufnr)
  if not bcache then
    return
  end

  local hunk = get_hunk(bufnr, bcache.hunks)
  if not hunk then
    return
  end

  local lines = create_patch(bcache.relpath, hunk, bcache.mode_bits)

  await_main()
  await(stage_lines, bcache.toplevel, lines)

  table.insert(bcache.staged_diffs, hunk)

  local signs = process_hunks({hunk})

  await_main()

  -- If watch_index is enabled then that will eventually kick in and update the
  -- signs, however for  smoother UX we can update the signs immediately without
  -- running a full diff.
  --
  -- We cannot update the status bar as that requires a full diff.
  for _, s in pairs(signs) do
    vim.fn.sign_unplace('gitsigns_ns', {buffer = bufnr, id = s.lnum})
  end
end)

local reset_hunk = function()
  local bufnr = current_buf()

  local bcache = get_cache_opt(bufnr)
  if not bcache then
    return
  end

  local hunk = get_hunk(bufnr, bcache.hunks)
  if not hunk then
    return
  end

  local orig_lines = vim.tbl_map(function(l)
      return string.sub(l, 2, -1)
    end, vim.tbl_filter(function(l)
      return vim.startswith(l, '-')
    end, hunk.lines))

  local lstart, lend
  if hunk.type == 'delete' then
      lstart = hunk.start
      lend = hunk.start
  else
    local length = vim.tbl_count(vim.tbl_filter(function(l)
      return vim.startswith(l, '+')
    end, hunk.lines))

    lstart = hunk.start - 1
    lend = hunk.start - 1 + length
  end
  api.nvim_buf_set_lines(bufnr, lstart, lend, false, orig_lines)
end

local undo_stage_hunk = async('undo_stage_hunk', function()
  local bufnr = current_buf()

  local bcache = get_cache_opt(bufnr)
  if not bcache then
    return
  end

  local hunk = bcache.staged_diffs[#bcache.staged_diffs]

  if not hunk then
    print("No hunks to undo")
    return
  end

  local lines = create_patch(bcache.relpath, hunk, bcache.mode_bits, true)

  await_main()
  await(stage_lines, bcache.toplevel, lines)

  table.remove(bcache.staged_diffs)

  local signs = process_hunks({hunk})

  await_main()
  add_signs(bufnr, signs)
end)

local function nav_hunk(forwards)
  local bcache = get_cache_opt(current_buf())
  if not bcache then
    return
  end
  local hunks = bcache.hunks
  if not hunks or vim.tbl_isempty(hunks) then
    return
  end
  local line = api.nvim_win_get_cursor(0)[1]
  local row
  if forwards then
    for i = 1, #hunks do
      local hunk = hunks[i]
      if hunk.start > line then
        row = hunk.start
        break
      end
    end
  else
    for i = #hunks, 1, -1 do
      local hunk = hunks[i]
      if hunk.dend < line then
        row = hunk.start
        break
      end
    end
  end
  -- wrap around
  if not row and vim.o.wrapscan then
    row = math.max(hunks[forwards and 1 or #hunks].start, 1)
  end
  if row then
    api.nvim_win_set_cursor(0, {row, 0})
  end
end

local function next_hunk() nav_hunk(true)  end
local function prev_hunk() nav_hunk(false) end

local detach = function(bufnr)
  dprint('Detached', bufnr)

  local bcache = get_cache_opt(bufnr)
  if not bcache then
    dprint('Cache was nil', bufnr)
    return
  end

  os.remove(bcache.staged)

  local w = bcache.index_watcher
  if w then
    w:stop()
  else
    dprint('Index_watcher was nil', bufnr)
  end

  cache[bufnr] = nil
end

local detach_all = function()
  for k, _ in pairs(cache) do
    detach(k)
  end
end

local function apply_keymaps(bufonly)
  apply_mappings(config.keymaps, bufonly)
end

local attach = throttle_leading(100, async('attach', function()
  local cbuf = current_buf()
  if cache[cbuf] ~= nil then
    dprint('Already attached', cbuf, 'attach')
    return
  end
  dprint('Attaching', cbuf, 'attach')
  local file = api.nvim_buf_get_name(cbuf)

  if not path_exists(file) or vim.fn.isdirectory(file) == 1 then
    dprint('Not a file', cbuf, 'attach')
    return
  end

  for _, p in ipairs(vim.split(file, '/')) do
    if p == '.git' then
        dprint('In git dir', cbuf, 'attach')
        return
    end
  end

  local toplevel, gitdir, abbrev_head = await(get_repo_info, file)

  if not gitdir then
    dprint('Not in git repo', cbuf, 'attach')
    return
  end

  set_buf_var(bufnr, 'gitsigns_head', abbrev_head)

  await_main()
  local relpath, object_name, mode_bits = await(git_relative, file, toplevel)

  if not relpath then
    dprint('File not tracked', cbuf, 'attach')
    return
  end

  local staged = os.tmpname()

  local res = await(get_staged, cbuf, staged, toplevel, relpath)
  if not res then
    return
  end

  cache[cbuf] = {
    file         = file,
    relpath      = relpath,
    object_name  = object_name,
    mode_bits    = mode_bits,
    toplevel     = toplevel,
    gitdir       = gitdir,
    abbrev_head  = abbrev_head,
    staged       = staged, -- Temp filename of staged file
    hunks        = {},
    staged_diffs = {}
  }

  cache[cbuf].index_watcher = await(watch_index, cbuf, gitdir,
    async0('watcher_cb', function()
      dprint('Index update', cbuf, 'watcher_cb')
      local bcache = get_cache(cbuf)

      await_main()
      local _, _, abbrev_head = await(get_repo_info, file)
      bcache.abbrev_head = abbrev_head
      set_buf_var(bufnr, 'gitsigns_head', abbrev_head)

      await_main()
      local _, object_name, mode_bits = await(git_relative, file, toplevel)
      if object_name == bcache.object_name then
         dprint('File not changed', cbuf, 'watcher_cb')
         return
      end
      bcache.object_name = object_name
      bcache.mode_bits = mode_bits
      local res = await(get_staged, cbuf, bcache.staged, toplevel, relpath)
      if not res then
         return
      end
      await(update, cbuf)
    end)
  )

  -- Initial update
  await(update, cbuf)

  await_main()

  api.nvim_buf_attach(cbuf, false, {
    on_lines = function(_, buf)
      update(buf)
    end,
    on_detach = function(_, buf)
      detach(buf)
    end
  })

  apply_keymaps(true)
end))

local function setup(cfg)
  config = apply_config(cfg)

  -- TODO: Attach to all open buffers

  gs_objs.init(config.debug_mode)

  -- Define signs
  for t, sign_name in pairs(sign_map) do
    sign_define(sign_name, config.signs[t].hl, config.signs[t].text)
  end

  apply_keymaps(false)

  -- This seems to be triggered twice on the first buffer so we have throttled
  -- the attach function with throttle_leading
  vim.cmd('autocmd BufRead * lua require("gitsigns").attach()')

  vim.cmd('autocmd ExitPre * lua require("gitsigns").detach_all()')
end

function preview_hunk()
  local hunk = get_hunk()

  if not hunk then
    return
  end

  validate.hunk(hunk)

  local winid, bufnr = gs_popup.create(hunk.lines, { relative = 'cursor' })

  vim.fn.nvim_buf_set_option(bufnr, 'filetype', 'diff')
  vim.fn.nvim_win_set_option(winid, 'number', false)
  vim.fn.nvim_win_set_option(winid, 'relativenumber', false)
end

function dump_cache()
  print(vim.inspect(cache))
end

return {
  update          = update,
  stage_hunk      = mk_repeatable(stage_hunk),
  undo_stage_hunk = mk_repeatable(undo_stage_hunk),
  reset_hunk      = mk_repeatable(reset_hunk),
  next_hunk       = next_hunk,
  prev_hunk       = prev_hunk,
  preview_hunk    = preview_hunk,
  attach          = attach,
  detach_all      = detach_all,
  setup           = setup,
  dump_cache      = dump_cache
}
