local Job = require('plenary.job')
local CM = require('plenary.context_manager')

local AS = require('gitsigns/async')
local default_config = require('gitsigns/defaults')

local api = vim.api
local current_buf = api.nvim_get_current_buf

local async = AS.async
local await = AS.await

local await_main = function()
  await(vim.schedule)
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

local function dprint(msg, caller)
  if config.debug_mode then
    local name = debug.getinfo(2, 'n').name
    vim.schedule(function()
      print('gitsigns('..(caller or name or '')..'): '..msg)
    end)
  end
end

local function dirname(file)
  return file:match("(.*/)")
end

local function relative(file, root)
  return string.sub(file, #root + 2)
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

-- to be used with await
local get_staged = function(root, path, callback)
  local relpath = relative(path, root)
  local content = {}
  Job:new {
    command = 'git',
    args = {'--no-pager', 'show', ':'..relpath},
    cwd = root,
    on_stdout = function(_, line, _)
      table.insert(content, line)
    end,
    on_exit = function(_, code)
      callback(code == 0 and content or nil)
    end
  }:start()
end

-- to be used with await
local run_diff = function(staged, current, callback)
  local results = {}
  Job:new {
    command = 'git',
    args = {'--no-pager', 'diff', '--patch-with-raw', '--unified=0', '--no-color', staged, current},
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
      dprint('error: '..line, 'run_diff')
    end,
    on_exit = function()
      callback(results)
    end
  }:start()
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
--   root: string - Root git directory (where .git is)
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
  local root
  Job:new {
    command = 'git',
    args = {'rev-parse', '--show-toplevel'},
    cwd = dirname(file),
    on_stdout = function(_, line)
      if line then
        root = line
      end
    end,
    on_exit = function()
      callback(root)
    end
  }:start()
end

local add_signs = function(bufnr, signs, reset)
  reset = reset or false

  if reset then
    vim.fn.sign_unplace('gitsigns_ns', {buffer = bufnr})
  end

  for _, s in pairs(signs) do
    vim.fn.sign_place(s.lnum, 'gitsigns_ns', sign_map[s.type], bufnr, {
      lnum = s.lnum, priority = 100
    })
  end
end

--- Throttles a function on the leading edge.
---
--@param fn (function) Function to throttle
--@param timeout (number) Timeout in ms
--@returns (function) throttled function
local function throttle_leading(ms, fn)
  local running = false
  return function(...)
    if not running then
      local timer = vim.loop.new_timer()
      timer:start(ms, 0, function()
        running = false
        timer:stop()
      end)
      running = true
      fn(...)
    end
  end
end

local update_cnt = 0

local update = throttle_leading(50, async(function(bufnr)
  await_main()
  bufnr = bufnr or current_buf()

  dprint(update_cnt, 'update')
  update_cnt = update_cnt + 1

  local file = api.nvim_buf_get_name(bufnr)
  local root = await(get_repo_root, file)
  if not root then
    -- Not in git repo
    return
  end

  await_main()

  local staged_txt = await(get_staged, root, file)
  if not staged_txt then
    -- File not in index
    return
  end

  await_main()
  local content = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local current = os.tmpname()
  write_to_file(current, content)

  local staged = os.tmpname()
  write_to_file(staged, staged_txt)

  local diffs = await(run_diff, staged, current)

  os.remove(staged)
  os.remove(current)

  cache[bufnr].file  = file
  cache[bufnr].root  = root
  cache[bufnr].diffs = diffs

  local status, signs = process_diffs(diffs)

  await_main()

  add_signs(bufnr, signs, true)

  api.nvim_buf_set_var(bufnr, 'gitsigns_status_dict', status)
  api.nvim_buf_set_var(bufnr, 'gitsigns_status', mk_status_txt(status))
end))

local watch_index = async(function(bufnr)
  local file = api.nvim_buf_get_name(bufnr)
  local root = await(get_repo_root, file)
  if root then
    dprint('Watching index: '..bufnr, 'watch_index')
    local w = vim.loop.new_fs_poll()
    w:start(root..'/.git/index', config.watch_index.interval,
      vim.schedule_wrap(function()
        update()
      end)
    )
    cache[bufnr].index_watcher = w
  end
end)

local stage_lines = function(root, lines, callback)
  local status = true
  local err = {}
  Job:new {
    command = 'git',
    args = {'apply', '--cached', '--unidiff-zero', '-'},
    cwd = root,
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
  }:start()
end

local function create_patch(relpath, hunk, invert)
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
    'index 000000..000000 100644', -- TODO: Get the correct perms
    '--- a/'..relpath,
    '+++ b/'..relpath,
    string.format('@@ -%s,%s +%s,%s @@', ps, pc, ns, nc),
    unpack(lines)
  }
end

local stage_hunk = async(function()
  local bufnr = current_buf()
  local bcache = cache[bufnr]
  local hunk = get_hunk(bufnr, bcache.diffs)

  if not hunk then
    return
  end

  local relpath = relative(bcache.file, bcache.root)
  local lines = create_patch(relpath, hunk)

  await(stage_lines, bcache.root, lines)

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

local reset_hunk = async(function()
  local bufnr = current_buf()
  local bcache = cache[bufnr]
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
end)

local undo_stage_hunk = async(function()
  local bufnr = current_buf()
  local bcache = cache[bufnr]

  local hunk = bcache.staged_diffs[#bcache.staged_diffs]

  if not hunk then
    print("No hunks to undo")
    return
  end

  local relpath = relative(bcache.file, bcache.root)
  local lines = create_patch(relpath, hunk, true)

  await(stage_lines, bcache.root, lines)

  table.remove(bcache.staged_diffs)

  local _, signs = process_diffs({hunk})

  await_main()
  add_signs(bufnr, signs)
end)

local function nav_hunk(forwards)
  local line = api.nvim_win_get_cursor(0)[1]
  local diffs = cache[current_buf()].diffs
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

local function keymap(mode, key, result)
  api.nvim_set_keymap(mode, key, result, {noremap = true, silent = true})
end

local attach = async(function()
  local cbuf = current_buf()
  cache[cbuf] = {
    file = nil,
    root = nil,
    diffs = {},
    staged_diffs = {},
    index_watcher = nil
  }

  if config.watch_index.enabled then
    await(watch_index, cbuf)
  else
    vim.cmd('autocmd CursorHold * lua require"gitsigns".update()')
  end

  -- Initial update
  await(update, cbuf)

  await_main()

  api.nvim_buf_attach(cbuf, false, {
    on_lines = function(_, buf)
      update(buf)
    end,
    on_detach = function(_, buf)
      dprint('Detached from '..buf, 'attach')

      local w = cache[buf].index_watcher
      if w then
        w:stop()
      else
        dprint('index_watcher for buf '..buf..' was nil', 'attach')
      end

      cache[buf] = nil
    end
  })
end)

local function setup(cfg)
  config = vim.tbl_deep_extend("keep", cfg or {}, default_config)

  -- Define signs
  for t, sign_name in pairs(sign_map) do
    vim.fn.sign_define(sign_name, {
      texthl = config.signs[t].hl,
      text   = config.signs[t].text
    })
  end

  -- Setup keymaps
  for key, cmd in pairs(config.keymaps) do
    keymap('n', key, cmd)
  end

  vim.cmd('autocmd BufRead * lua require("gitsigns").attach()')
end

return {
  update     = update,
  stage_hunk = stage_hunk,
  undo_stage_hunk = undo_stage_hunk,
  reset_hunk = reset_hunk,
  next_hunk  = next_hunk,
  prev_hunk  = prev_hunk,
  attach     = attach,
  setup      = setup,
}
