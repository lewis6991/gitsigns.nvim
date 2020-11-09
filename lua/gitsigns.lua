local Job = require('plenary/job')
local Path = require('plenary/path')
local CM = require('plenary/context_manager')

local AS = require('gitsigns/async')
local default_config = require('gitsigns/defaults')
local mk_repeatable = require('gitsigns/repeat').mk_repeatable
local DB = require('gitsigns/debounce')
local apply_mappings = require('gitsigns/mappings')

local throttle_leading = DB.throttle_leading
local debounce_trailing = DB.debounce_trailing

local api = vim.api
local current_buf = api.nvim_get_current_buf

local async  = AS.async
local async0 = AS.async0
local await  = AS.await

local await_main = function()
  return await(vim.schedule)
end

local with = CM.with
local open = CM.open

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

local function parse_diff_line(line)
  local diffkey = vim.trim(vim.split(line, '@@', true)[2])

  -- diffKey: "-xx,n +yy"
  -- pre: {xx, n}, now: {yy}
  local pre, now = unpack(vim.tbl_map(function(s)
    return vim.split(string.sub(s, 2), ',')
  end, vim.split(diffkey, ' ')))

  local removed = { start = tonumber(pre[1]), count = tonumber(pre[2]) or 1 }
  local added   = { start = tonumber(now[1]), count = tonumber(now[2]) or 1 }

  local diff = {
    start   = added.start,
    head    = line,
    lines   = {},
    removed = removed,
    added   = added
  }

  if added.count == 0 then
    -- delete
    diff.dend = added.start
    diff.type = "delete"
  elseif removed.count == 0 then
    -- add
    diff.dend = added.start + added.count - 1
    diff.type = "add"
  else
    -- change
    diff.dend = added.start + math.min(added.count, removed.count) - 1
    diff.type = "change"
  end
  return diff
end

local function write_to_file(file, content)
  with(open(file, 'w'), function(writer)
    for _, l in pairs(content) do
      writer:write(l..'\n')
    end
  end)
end

local function update_status(status, diff)
  if diff.type == 'add' then
    status.added = status.added + diff.added.count
  elseif diff.type == 'delete' then
    status.removed = status.removed + diff.removed.count
  elseif diff.type == 'change' then
    local add, remove = diff.added.count, diff.removed.count
    local min = math.min(add, remove)
    status.changed = status.changed + min
    status.added   = status.added   + add - min
    status.removed = status.removed + remove - min
  end
end

local function process_diffs(diffs)
  local status = { added = 0, changed = 0, removed = 0 }

  local signs = {}
  local add_sign = function(type, lnum)
    table.insert(signs, {type = type, lnum = lnum})
  end

  for _, diff in pairs(diffs) do
    update_status(status, diff)

    for i = diff.start, diff.dend do
      local topdelete = diff.type == 'delete' and i == 0
      local changedelete = diff.type == 'change' and diff.removed.count > diff.added.count and i == diff.dend
      add_sign(
        topdelete and 'topdelete' or changedelete and 'changedelete' or diff.type,
        topdelete and 1 or i
      )
    end
    if diff.type == "change" then
      local add, remove = diff.added.count, diff.removed.count
      if add > remove then
        for i = 1, add - remove do
          add_sign('add', diff.dend + i)
        end
      end
    end
  end

  return status, signs
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
    on_stdout = function(_, line, _)
      if line then
        local parts = vim.split(line, ' +')
        mode_bits   = parts[1]
        object_name = parts[2]
        relpath = vim.split(parts[3], '\t', true)[2]
      end
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
    on_stdout = function(_, line, _)
      table.insert(content, line)
    end,
    on_exit = function(_, code)
      callback(code == 0 and content or nil)
    end
  }
end

local get_diff_algorithm = function()
  local algo = 'myers'
  for o in vim.gsplit(vim.o.diffopt, ',') do
    if vim.startswith(o, 'algorithm:') then
      algo = string.sub(o, 11)
    end
  end
  return algo
end

local algo = get_diff_algorithm()

local run_diff = function(staged, text, callback)
  local results = {}
  run_job {
    command = 'git',
    args = {
      '--no-pager',
      'diff',
      '--diff-algorithm='..algo,
      '--patch-with-raw',
      '--unified=0',
      '--no-color',
      staged,
      '-'
    },
    -- For some strange reason, if lines are fed one by one to git diff via a
    -- pipe, it stops reading at line ~278. Some internal buffer limit?. To
    -- workaround this we pass the file as a single string by concatenating
    -- all the lines.
    writer = table.concat(text, '\n')..'\n',
    on_stdout = function(_, line, _)
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

local function mk_status_txt(status)
  local added, changed, removed = status.added, status.changed, status.removed
  local status_txt = {}
  if added   > 0 then table.insert(status_txt, '+'..added  ) end
  if changed > 0 then table.insert(status_txt, '~'..changed) end
  if removed > 0 then table.insert(status_txt, '-'..removed) end
  return table.concat(status_txt, ' ')
end

local cache = {}
-- <bufnr> = {
--   file: string - Full filename
--   relpath: string - Relative path to toplevel
--   object_name: string - Object name of file in index
--   mode_bits: string
--   toplevel: string - Top level git directory
--   gitdir: string - Path to git directory
--   staged: string - Path to staged contents
--   diffs: array(diffs) - List of diff objects
--   staged_diffs: array(diffs) - List of staged diffs
--   index_watcher: Timer object watching the files index
-- }

local function find_diff(line, diffs)
  for _, diff in pairs(diffs) do
    if line == 1 and diff.start == 0 and diff.dend == 0 then
      return diff
    end

    local dend =
      diff.type == 'change' and diff.added.count > diff.removed.count and
        (diff.dend + diff.added.count - diff.removed.count) or
        diff.dend

    if diff.start <= line and dend >= line then
      return diff
    end
  end
end

local function get_hunk(bufnr, diffs)
  bufnr = bufnr or current_buf()
  diffs = diffs or cache[bufnr].diffs

  local line = api.nvim_win_get_cursor(0)[1]
  return find_diff(line, diffs)
end

local get_repo_root = function(file, callback)
  local out = {}
  run_job {
    command = 'git',
    args = {'rev-parse', '--show-toplevel', '--absolute-git-dir'},
    cwd = dirname(file),
    on_stdout = function(_, line)
      if line then
        table.insert(out, line)
      end
    end,
    on_exit = function()
      local toplevel = out[1]
      local gitdir = out[2]
      callback(toplevel, gitdir)
    end
  }
end

local add_signs = function(bufnr, signs, reset)
  reset = reset or false

  if reset then
    vim.fn.sign_unplace('gitsigns_ns', {buffer = bufnr})
  end

  for _, s in pairs(signs) do
    vim.fn.sign_place(s.lnum, 'gitsigns_ns', sign_map[s.type], bufnr, {
      lnum = s.lnum, priority = config.sign_priority
    })
  end
end

local v

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

  local bcache = cache[bufnr]
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
  bcache.diffs = await(run_diff, staged, buftext)

  local status, signs = process_diffs(bcache.diffs)

  await_main()

  add_signs(bufnr, signs, true)

  api.nvim_buf_set_var(bufnr, 'gitsigns_status_dict', status)
  api.nvim_buf_set_var(bufnr, 'gitsigns_status', mk_status_txt(status))

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

local create_patch = function(relpath, hunk, mode_bits, invert)
  invert = invert or false
  local type, added, removed = hunk.type, hunk.added, hunk.removed

  local ps, pc, ns, nc = unpack(({
    add    = {removed.start + 1, 0            , removed.start + 1, added.count},
    delete = {removed.start    , removed.count, removed.start    , 0          },
    change = {removed.start    , removed.count, removed.start    , added.count}
  })[type])

  local lines = hunk.lines

  if invert then
    ps, pc, ns, nc = ns, nc, ps, pc

    lines = vim.tbl_map(function(l)
      if vim.startswith(l, '+') then
        l = '-'..string.sub(l, 2, -1)
      elseif vim.startswith(l, '-') then
        l = '+'..string.sub(l, 2, -1)
      end
      return l
    end, lines)
  end

  return {
    string.format('diff --git a/%s b/%s', relpath, relpath),
    'index 000000..000000 '..mode_bits,
    '--- a/'..relpath,
    '+++ b/'..relpath,
    string.format('@@ -%s,%s +%s,%s @@', ps, pc, ns, nc),
    unpack(lines)
  }
end

local stage_hunk = async('stage_hunk', function()
  local bufnr = current_buf()

  local bcache = cache[bufnr]
  if not bcache then
    return
  end

  local hunk = get_hunk(bufnr, bcache.diffs)
  if not hunk then
    return
  end

  local lines = create_patch(bcache.relpath, hunk, bcache.mode_bits)

  await_main()
  await(stage_lines, bcache.toplevel, lines)

  table.insert(bcache.staged_diffs, hunk)

  local _, signs = process_diffs({hunk})

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

  local bcache = cache[bufnr]
  if not bcache then
    return
  end

  local hunk = get_hunk(bufnr, bcache.diffs)
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

  local bcache = cache[bufnr]
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

  local _, signs = process_diffs({hunk})

  await_main()
  add_signs(bufnr, signs)
end)

local function nav_hunk(forwards)
  local bcache = cache[current_buf()]
  if not bcache then
    return
  end
  local diffs = bcache.diffs
  if not diffs or vim.tbl_isempty(diffs) then
    return
  end
  local line = api.nvim_win_get_cursor(0)[1]
  local row
  if forwards then
    for i = 1, #diffs do
      local diff = diffs[i]
      if diff.start > line then
        row = diff.start
        break
      end
    end
  else
    for i = #diffs, 1, -1 do
      local diff = diffs[i]
      if diff.dend < line then
        row = diff.start
        break
      end
    end
  end
  -- wrap around
  if not row and vim.o.wrapscan then
    row = math.max(diffs[forwards and 1 or #diffs].start, 1)
  end
  if row then
    api.nvim_win_set_cursor(0, {row, 0})
  end
end

local function next_hunk() nav_hunk(true)  end
local function prev_hunk() nav_hunk(false) end

local detach = function(bufnr)
  dprint('Detached', bufnr)

  local bcache = cache[bufnr]
  if not bcache then
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

  if not path_exists(file) then
    dprint('Not a file', cbuf, 'attach')
    return
  end

  local toplevel, gitdir = await(get_repo_root, file)

  if not gitdir then
    dprint('Not in git repo', cbuf, 'attach')
    return
  end

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
    staged       = staged, -- Temp filename of staged file
    diffs        = {},
    staged_diffs = {}
  }

  cache[cbuf].index_watcher = await(watch_index, cbuf, gitdir,
    async0('watcher_cb', function()
      dprint('Index update', cbuf, 'watcher_cb')
      local bcache = cache[cbuf]
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
  if cfg.keymaps and not vim.tbl_isempty(cfg.keymaps) then
    default_config.keymaps = {}
  end

  config = vim.tbl_deep_extend("keep", cfg or {}, default_config)

  -- Define signs
  for t, sign_name in pairs(sign_map) do
    vim.fn.sign_define(sign_name, {
      texthl = config.signs[t].hl,
      text   = config.signs[t].text
    })
  end

  apply_keymaps(false)

  -- This seems to be triggered twice on the first buffer so we have throttled
  -- the attach function with throttle_leading
  vim.cmd('autocmd BufRead * lua require("gitsigns").attach()')

  vim.cmd('autocmd ExitPre * lua require("gitsigns").detach_all()')
end

return {
  update          = update,
  stage_hunk      = mk_repeatable(stage_hunk),
  undo_stage_hunk = mk_repeatable(undo_stage_hunk),
  reset_hunk      = mk_repeatable(reset_hunk),
  next_hunk       = next_hunk,
  prev_hunk       = prev_hunk,
  attach          = attach,
  detach_all      = detach_all,
  setup           = setup,
}
