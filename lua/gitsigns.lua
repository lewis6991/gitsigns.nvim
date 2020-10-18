local Job = require('plenary.job')
local CM = require('plenary.context_manager')

local AS = require('gitsigns/async')
local default_config = require('gitsigns/defaults')

local function dprint(msg)
  vim.schedule(function()
    print(msg)
  end)
end

local api = vim.api
local current_buf = api.nvim_get_current_buf


local async = AS.async
local await = AS.await
local awrap = AS.awrap

local with = CM.with
local open = CM.open

local count = 0

local config = {}

local sign_map = {
  add          = "GitSignsAdd",
  delete       = "GitSignsDelete",
  change       = "GitSignsChange",
  topdelete    = "GitSignsTopDelete",
  changedelete = "GitSignsChangeDelete",
}

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
local get_staged = awrap(function(root, path, callback)
  local relpath = relative(path, root)
  local content = {}
  local valid = true
  Job:new {
    command = 'git',
    args = {'--no-pager', 'show', ':'..relpath},
    cwd = root,
    on_stdout = function(_, line, _)
      table.insert(content, line)
    end,
    on_stderr = function(_, line)
      dprint('ERR: '..path)
      dprint('ERR: '..line)
      valid = false
    end,
    on_exit = function()
      callback(valid, content)
    end
  }:start()
end)

-- to be used with await
local run_diff = awrap(function(staged, current, callback)
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
    on_exit = function()
      callback(results)
    end
  }:start()
end)

local function mk_status_txt(status)
  local added, changed, removed = status.added, status.changed, status.removed
  local status_txt = {}
  if added   > 0 then table.insert(status_txt, '+'..added  ) end
  if changed > 0 then table.insert(status_txt, '~'..changed) end
  if removed > 0 then table.insert(status_txt, '-'..removed) end
  return table.concat(status_txt, ' ')
end

local cache = {}

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

local get_repo_root = awrap(function(file, callback)
  local root
  Job:new {
    command = 'git',
    args = {'rev-parse', '--show-toplevel'},
    cwd = dirname(file),
    on_stderr = function(_, line)
      print(line)
    end,
    on_stdout = function(_, line)
      if line then
        root = line
      end
    end,
    on_exit = function()
      callback(root)
    end
  }:start()
end)

local function update2(bufnr)
  async(function()
    await(vim.schedule)
    bufnr = bufnr or current_buf()

    local content = api.nvim_buf_get_lines(bufnr, 0, -1, false)
    -- local current = os.tmpname()
    local current = '/tmp/current'
    write_to_file(current, content)

    local file = api.nvim_buf_get_name(bufnr)
    local root = await(get_repo_root(file))
    if not root then
      return
    end

    await(vim.schedule)

    local valid, staged_txt = await(get_staged(root, file))

    if not valid then
      return
    end

    -- local staged = os.tmpname()
    local staged = '/tmp/staged'
    write_to_file(staged, staged_txt)

    local diffs = await(run_diff(staged, current))

    cache[bufnr] = {
      file    = file,
      git_dir = root,
      diffs   = diffs,
    }

    local status, signs = process_diffs(diffs)

    await(vim.schedule)

    vim.fn.sign_unplace('gitsigns_ns', {buffer = bufnr})
    for _, s in pairs(signs) do
      vim.fn.sign_place(0, 'gitsigns_ns', sign_map[s.type], bufnr, { lnum = s.lnum, priority = 100 })
    end

    api.nvim_buf_set_var(bufnr, 'git_signs_status_dict', status)
    api.nvim_buf_set_var(bufnr, 'git_signs_status', mk_status_txt(status))

    -- print("UPDATE: " .. count)
    -- count = count + 1
  end)()
end

local function update(bufnr)
  local status, err = pcall(update2, bufnr)
  if not status then
    dprint(err)
    dprint(debug.traceback())
  end
end

local w = vim.loop.new_fs_poll()

local function watch_file(fname)
  w:start(fname, config.watch_index.interval,
    vim.schedule_wrap(function(err, prev, curr)
      update()
    end)
  )
end

local function watch_index(file)
  async(function()
    local root = await(get_repo_root(file))
    if root then
      watch_file(root..'/.git/index')
    end
  end)()
end

local stage_lines = awrap(function(root, lines, callback)
  Job:new {
    command = 'git',
    args = {'apply', '--cached', '--unidiff-zero', '-'},
    cwd = root,
    writer = lines,
    on_stderr = function(_, line)
      print(line)
    end,
    on_exit = callback
  }:start()
end)

local function stage_hunk()
  local bufnr = current_buf()

  local bcache = cache[bufnr]

  local hunk = get_hunk(bufnr, bcache.diffs)
  if not hunk then
    return
  end

  local type, added, removed = hunk.type, hunk.added, hunk.removed

  local ps, pc, ns, nc

  if type == 'add' then
    ps, pc, ns, nc = removed.start + 1, 0            , removed.start + 1, added.count
  elseif type == 'delete' then
    ps, pc, ns, nc = removed.start    , removed.count, removed.start    , 0
  elseif type == 'change' then
    ps, pc, ns, nc = removed.start    , removed.count, removed.start    , added.count
  end

  local head = string.format('@@ -%s,%s +%s,%s @@', ps, pc, ns, nc)

  async(function()
    local relpath = relative(bcache.file, bcache.git_dir)

    local lines = {
      string.format('diff --git a/%s b/%s', relpath, relpath),
      'index 000000..000000 100644',
      '--- a/'..relpath,
      '+++ b/'..relpath,
      head,
      unpack(hunk.lines)
    }

    await(vim.schedule)
    await(stage_lines(bcache.git_dir, lines))
    update(bufnr)
  end)()
end

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
  api.nvim_buf_set_keymap(0, mode, key, result, {noremap = true, silent = true})
end

local function attach()
  local cbuf = current_buf()

  if config.watch_index.enabled then
    local file = api.nvim_buf_get_name(cbuf)
    watch_index(file)
  else
    vim.cmd('autocmd CursorHold * lua require"gitsigns".update()')
  end

  -- Initial update
  update(cbuf)

  api.nvim_buf_attach(cbuf, false, {
    on_lines = function(_, buf, ct, first, last, lastu, bc, dcp, dcu)
      update(buf)
    end,
    on_detach = function(_, buf)
      cache[buf] = nil
      dprint("Detached from "..buf)
    end
  })
end


local function setup(cfg)
  config = vim.tbl_deep_extend("keep", cfg or {}, default_config)

  -- Define signs
  for t, sign_name in pairs(sign_map) do
    vim.fn.sign_define(sign_map[t], {
      texthl = config.signs[t].hl,
      text   = config.signs[t].text
    })
  end

  -- Setup keymaps
  for key, cmd in pairs(config.keymaps) do
    keymap('n', key, cmd)
  end

  vim.cmd('autocmd BufRead * lua require"gitsigns".attach()')
end

return {
  update     = update,
  get_hunk   = get_hunk,
  stage_hunk = stage_hunk,
  next_hunk  = next_hunk,
  prev_hunk  = prev_hunk,
  attach     = attach,
  setup      = setup,
}
