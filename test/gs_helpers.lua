local helpers = require('nvim-test.helpers')

local timeout = 2000

local M = helpers

local exec_lua = helpers.exec_lua
local matches = helpers.matches
local eq = helpers.eq
local buf_get_var = helpers.api.nvim_buf_get_var
local system = helpers.fn.system
local nvim_test_clear = helpers.clear
local uv = vim.uv or vim.loop ---@diagnostic disable-line: deprecated

--- @return boolean
local function is_win()
  return M.fn.has('win32') == 1
end

--- @return boolean
local function has_cygpath()
  return is_win() and M.fn.executable('cygpath') == 1
end

--- @param path string
local function local_stat(path)
  return uv.fs_stat(path)
end

--- @param path string
--- @return boolean
local function local_exists(path)
  return local_stat(path) ~= nil
end

--- @param path string
--- @param mode? 'unix'|'windows'|'mixed'
--- @return string
local function local_cygpath(path, mode)
  return vim.trim(M.fn.system({ 'cygpath', '--absolute', '--' .. (mode or 'mixed'), path }))
end

--- @return string
local function local_tmpdir()
  return assert(uv.os_tmpdir() or '/tmp')
end

--- @param timeout integer
local function drain_session_gc(timeout)
  if not is_win() or not M.get_session() then
    return
  end

  M.exec_lua(function(timeout0)
    collectgarbage('collect')
    collectgarbage('collect')
    vim.wait(timeout0, function()
      collectgarbage('collect')
      return false
    end, 10)
  end, timeout)
end

--- @param path string
local function local_delete_once(path)
  local stat = local_stat(path)
  if not stat then
    return
  end

  if stat.type == 'directory' then
    local handle = uv.fs_scandir(path)
    if handle then
      while true do
        local name = uv.fs_scandir_next(handle)
        if not name then
          break
        end
        local_delete_once(path .. '/' .. name)
      end
    end
    assert(uv.fs_rmdir(path))
  else
    assert(uv.fs_unlink(path))
  end
end

--- @param err string
--- @return boolean
local function is_retryable_delete_error(err)
  return err:find('EBUSY', 1, true) ~= nil
    or err:find('EPERM', 1, true) ~= nil
    or err:find('ENOTEMPTY', 1, true) ~= nil
end

--- @param path string
local function local_delete(path)
  local retries = is_win() and 100 or 1

  for attempt = 1, retries do
    local ok, err = pcall(local_delete_once, path)
    if ok then
      return
    end

    if attempt == retries or not is_retryable_delete_error(err) then
      error(err, 0)
    end

    drain_session_gc(50)
    M.sleep(50)
  end
end

local scratch_root = os.getenv('PJ_ROOT') .. '/scratch'
local scratch_session = scratch_root
  .. '/session-'
  .. tostring(uv.os_getpid and uv.os_getpid() or 0)
  .. '-'
  .. tostring(uv.hrtime())
local scratch_seq = 0
local empty_repo_seed = scratch_session .. '/seed-empty'
local default_repo_seed = scratch_session .. '/seed-default'

--- @param path string
local function set_scratch(path)
  M.scratch = path
  M.test_file = path .. '/dummy.txt'
  M.newfile = path .. '/newfile.txt'
end

local function next_scratch()
  scratch_seq = scratch_seq + 1
  return scratch_session .. ('/test-%04d'):format(scratch_seq)
end

local function reset_scratch()
  set_scratch(next_scratch())
end

reset_scratch()

M.test_config = {
  debug_mode = true,
  _test_mode = true,
  _allow_fs_poll_fallback = os.getenv('GITSIGNS_TEST_ALLOW_FS_POLL_FALLBACK') ~= '0',
  watch_gitdir = {
    enable = false,
    follow_files = true,
  },
  signs = {
    add = { text = '+' },
    delete = { text = '_' },
    change = { text = '~' },
    topdelete = { text = '^' },
    changedelete = { text = '%' },
    untracked = { text = '#' },
  },
  on_attach = {
    { 'n', 'mhs', '<cmd>lua require"gitsigns".stage_hunk()<CR>' },
    { 'n', 'mhu', '<cmd>lua require"gitsigns".undo_stage_hunk()<CR>' },
    { 'n', 'mhr', '<cmd>lua require"gitsigns".reset_hunk()<CR>' },
    { 'n', 'mhp', '<cmd>lua require"gitsigns".preview_hunk()<CR>' },
    { 'n', 'mhS', '<cmd>lua require"gitsigns".stage_buffer()<CR>' },
    { 'n', 'mhU', '<cmd>lua require"gitsigns".reset_buffer_index()<CR>' },
  },
  attach_to_untracked = true,
  update_debounce = 5,
}

local test_file_text = {
  'This',
  'is',
  'a',
  'file',
  'used',
  'for',
  'testing',
  'gitsigns.',
  'The',
  'content',
  "doesn't",
  'matter,',
  'it',
  'just',
  'needs',
  'to',
  'be',
  'static.',
}

--- Run a git command
--- @param ... string
function M.git(...)
  local args = { ... } --- @type string[]
  local scratch0 = assert(M.normalize_path(M.scratch))

  for i, arg in ipairs(args) do
    local normalized = M.normalize_path(arg)
    if normalized and vim.startswith(normalized, scratch0 .. '/') then
      args[i] = normalized:sub(#scratch0 + 2)
    end
  end

  system(vim.list_extend({ 'git', '-C', M.scratch }, args))
end

--- @param cmd string[]
--- @param errmsg string
local function system_ok(cmd, errmsg)
  local output = system(cmd)
  eq(0, exec_lua('return vim.v.shell_error'), ('%s\n%s'):format(errmsg, output))
end

--- @param path string
--- @param ... string
local function git_in(path, ...)
  system_ok(
    vim.list_extend({ 'git', '-C', path }, { ... }),
    ('git command failed in %s'):format(path)
  )
end

local function configure_git_repo(path)
  -- Always force color to test settings don't interfere with gitsigns system
  -- commands (addresses #23).
  git_in(path, 'config', 'color.branch', 'always')
  git_in(path, 'config', 'color.ui', 'always')
  git_in(path, 'config', 'color.diff', 'always')
  git_in(path, 'config', 'color.interactive', 'always')
  git_in(path, 'config', 'color.status', 'always')
  git_in(path, 'config', 'color.grep', 'always')
  git_in(path, 'config', 'color.pager', 'true')
  git_in(path, 'config', 'color.decorate', 'always')
  git_in(path, 'config', 'color.showbranch', 'always')
  git_in(path, 'config', 'core.autocrlf', 'false')
  git_in(path, 'config', 'core.eol', 'lf')

  git_in(path, 'config', 'merge.conflictStyle', 'merge')

  git_in(path, 'config', 'user.email', 'tester@com.com')
  git_in(path, 'config', 'user.name', 'tester')

  git_in(path, 'config', 'init.defaultBranch', 'main')
end

--- @param path string
local function init_git_repo(path)
  if local_exists(path) then
    local_delete(path)
  end

  M.mkdir(path)
  git_in(path, 'init', '-b', 'main')
  configure_git_repo(path)
end

--- @param src string
--- @param dst string
local function local_copy_dir_fallback(src, dst)
  local stat = assert(local_stat(src), ('failed to stat %s'):format(src))
  if stat.type == 'directory' then
    M.mkdir(dst)

    local handle = uv.fs_scandir(src)
    if not handle then
      return
    end

    while true do
      local name = uv.fs_scandir_next(handle)
      if not name then
        break
      end
      local_copy_dir_fallback(src .. '/' .. name, dst .. '/' .. name)
    end
    return
  end

  assert(uv.fs_copyfile(src, dst))
end

--- @param src string
--- @param dst string
local function copy_dir(src, dst)
  local parent = vim.fs.dirname(dst)
  if parent then
    M.mkdir(parent)
  end

  if is_win() then
    local_copy_dir_fallback(src, dst)
    return
  end

  system_ok({ 'cp', '-R', src, dst }, ('failed to copy %s to %s'):format(src, dst))
end

--- @return string
local function ensure_empty_repo_seed()
  if not local_exists(empty_repo_seed) then
    init_git_repo(empty_repo_seed)
  end
  return empty_repo_seed
end

--- @return string
local function ensure_default_repo_seed()
  if not local_exists(default_repo_seed) then
    copy_dir(ensure_empty_repo_seed(), default_repo_seed)
    M.write_to_file(default_repo_seed .. '/dummy.txt', test_file_text)
    git_in(default_repo_seed, 'add', 'dummy.txt')
    git_in(default_repo_seed, 'commit', '-m', 'init commit')
  end
  return default_repo_seed
end

function M.cleanup()
  if M.get_session() then
    if M.fn.isdirectory(M.scratch) == 0 and M.fn.filereadable(M.scratch) == 0 then
      return
    end

    M.exec_lua(function(root, tmpdir0)
      pcall(function()
        require('gitsigns').detach_all()
      end)
      pcall(vim.cmd, 'silent! noautocmd enew!')
      pcall(vim.cmd, 'silent! cd ' .. vim.fn.fnameescape(tmpdir0))

      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        local name = vim.api.nvim_buf_get_name(buf)
        if name ~= '' and name:find(root, 1, true) then
          pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end
      end
    end, M.scratch, local_tmpdir())

    if is_win() then
      drain_session_gc(100)
    end

    if not is_win() and M.fn.delete(M.scratch, 'rf') == 0 then
      return
    end
  end

  if not local_exists(M.scratch) then
    return
  end

  local_delete(M.scratch)
end

function M.cleanup_scratch_root()
  M.cleanup()

  if not local_exists(scratch_root) then
    return
  end

  local_delete(scratch_root)
end

--- Starts a new global Nvim session and allocates an isolated scratch repo.
--- @param init_lua_path? string
function M.clear(init_lua_path)
  M.cleanup()
  nvim_test_clear(init_lua_path)
  reset_scratch()
end

--- @param path string
function M.mkdir(path)
  if M.fn.isdirectory(path) == 1 then
    return
  end

  eq(1, M.fn.mkdir(path, 'p'), ('failed to create %s'):format(path))
end

--- @param src string
--- @param dst string
function M.move(src, dst)
  eq(0, M.fn.rename(src, dst), ('failed to move %s to %s'):format(src, dst))
end

--- @param path string
function M.touch(path)
  local parent = vim.fs.dirname(path)
  if parent then
    M.mkdir(parent)
  end

  local f = assert(io.open(path, 'ab'))
  f:close()
end

--- @param path string?
--- @return string?
function M.normalize_path(path)
  if not path or path == '' then
    return path
  end

  if has_cygpath() and path:match('^/[A-Za-z]/') then
    path = local_cygpath(path, 'mixed')
  end

  if is_win() then
    path = path:gsub('\\', '/')
  end

  return vim.fs.normalize(path)
end

--- @param expected string?
--- @param actual string?
--- @param msg? string
function M.eq_path(expected, actual, msg)
  eq(M.normalize_path(expected), M.normalize_path(actual), msg)
end

--- @param path string
--- @return string
function M.path_pattern(path)
  local normalized = assert(M.normalize_path(path))

  local is_abs = normalized:match('^%a:/') ~= nil or normalized:match('^/') ~= nil
  local stripped = normalized:gsub('^%a:/', ''):gsub('^/[A-Za-z]/', ''):gsub('^/+', '')

  local parts = vim.split(stripped, '/', { plain = true, trimempty = true })
  local pattern = table.concat(vim.tbl_map(vim.pesc, parts), '[\\/]')

  if is_abs then
    return '.*[\\/]?' .. pattern
  end

  return pattern
end

function M.git_init_scratch()
  M.cleanup()
  copy_dir(ensure_empty_repo_seed(), M.scratch)
end

--- Setup a basic git repository in directory `helpers.scratch` with a single file
--- `helpers.test_file` committed.
--- @param opts? {test_file_text?: string[], no_add?: boolean}
function M.setup_test_repo(opts)
  local text = opts and opts.test_file_text or test_file_text
  if not (opts and opts.no_add) and vim.deep_equal(text, test_file_text) then
    M.cleanup()
    copy_dir(ensure_default_repo_seed(), M.scratch)
    return
  end

  M.git_init_scratch()
  M.write_to_file(M.test_file, text)
  if not (opts and opts.no_add) then
    M.git('add', M.test_file)
    M.git('commit', '-m', 'init commit')
  end
end

--- @param cond fun()
--- @param interval? integer
function M.expectf(cond, interval)
  local duration = 0
  interval = interval or 1
  while duration < timeout do
    local ok, ret = pcall(cond)
    if ok and (ret == nil or ret == true) then
      return
    end
    duration = duration + interval
    helpers.sleep(interval)
    interval = math.min(interval * 2, 50)
  end
  cond()
end

--- @return boolean
function M.supports_source_hls()
  return M.fn.has('nvim-0.12') == 1
end

function M.require_source_hls()
  if not M.supports_source_hls() then
    M.pending('requires Neovim 0.12+')
  end
end

--- @param hl string|string[]?
--- @param group string
--- @return boolean
function M.contains_hl(hl, group)
  if type(hl) == 'table' then
    return vim.tbl_contains(hl, group)
  end
  return hl == group
end

--- @param range [integer, integer]?
function M.stage_hunk(range)
  M.exec_lua(function(range0)
    local async = require('gitsigns.async')

    if range0 == vim.NIL then
      range0 = nil
    end

    async
      .run(function()
        local err = async.await(1, function(cb)
          require('gitsigns').stage_hunk(range0, nil, cb)
        end)
        assert(not err, err)
      end)
      :wait(5000)
  end, range == nil and vim.NIL or range)
end

function M.reset_buffer_index()
  M.exec_lua(function()
    local async = require('gitsigns.async')
    async
      .run(function()
        local err = async.await(1, require('gitsigns').reset_buffer_index)
        assert(not err, err)
      end)
      :wait(5000)
  end)
end

--- @param path string
function M.edit(path)
  helpers.api.nvim_command('edit! ' .. M.fn.fnameescape(path))
end

--- Run a command and wait for the buffer's next GitSignsUpdate event.
--- @param cmd string
--- @param bufnr? integer
function M.command_wait_gitsigns_update(cmd, bufnr)
  M.exec_lua(function(cmd0, bufnr0)
    local async = require('gitsigns.async')
    local target_bufnr = bufnr0 == vim.NIL and vim.api.nvim_get_current_buf() or bufnr0

    async
      .run(function()
        local event = async.event()
        local group = vim.api.nvim_create_augroup('gitsigns_test_wait_update', { clear = true })
        local autocmd --- @type integer

        autocmd = vim.api.nvim_create_autocmd('User', {
          group = group,
          pattern = 'GitSignsUpdate',
          callback = function(args)
            if args.data and args.data.buffer == target_bufnr then
              pcall(vim.api.nvim_del_autocmd, autocmd)
              event:set()
            end
          end,
        })

        local ok, err = pcall(vim.cmd, cmd0)
        if not ok then
          pcall(vim.api.nvim_del_augroup_by_id, group)
          error(err)
        end

        event:wait()
        pcall(vim.api.nvim_del_augroup_by_id, group)
      end)
      :wait(5000)
  end, cmd, bufnr == nil and vim.NIL or bufnr)
end

--- @param bufnr? integer
function M.wait_for_attach(bufnr)
  M.expectf(function()
    return M.exec_lua(function(bufnr0)
      if bufnr0 == vim.NIL then
        bufnr0 = 0
      end
      local cache = require('gitsigns.cache').cache[bufnr0]
      return cache ~= nil
        and cache.git_obj ~= nil
        and cache.hunks ~= nil
        and vim.b[bufnr0].gitsigns_status_dict.gitdir ~= nil
    end, bufnr == nil and vim.NIL or bufnr)
  end)

  M.match_debug_messages({
    ('attach.attach(%d): attach complete'):format(bufnr or M.api.nvim_get_current_buf()),
  })
end

--- @param path string
--- @param text string[]
--- @param opts? {newline?: string, trailing_newline?: boolean}
function M.write_to_file(path, text, opts)
  opts = opts or {}

  local parent = vim.fs.dirname(path)
  if parent then
    M.mkdir(parent)
  end

  local newline = opts.newline or '\n'
  local trailing_newline = opts.trailing_newline
  if trailing_newline == nil then
    trailing_newline = #text > 0
  end

  local f = assert(io.open(path, 'wb'))
  for i, l in ipairs(text) do
    if i > 1 then
      f:write(newline)
    end
    f:write(l)
  end
  if trailing_newline then
    f:write(newline)
  end
  f:close()
end

--- @return string
function M.tempname()
  return M.fn.tempname()
end

function M.chdir_tmp()
  M.api.nvim_command('cd ' .. M.fn.fnameescape(local_tmpdir()))
end

--- @param line string
--- @param spec string|{next:boolean, pattern:boolean, text:string}
--- @return boolean
local function match_spec_elem(line, spec)
  if spec.pattern then
    if line:match(spec.text) then
      return true
    end
  elseif spec.next then
    -- local matcher = spec.pattern and matches or eq
    -- matcher(spec.text, line)
    if spec.pattern then
      matches(spec.text, line)
    else
      eq(spec.text, line)
    end
    return true
  end

  return spec == line
end

--- Match lines in spec. Not all lines have to match
--- @param lines string[]
--- @param spec table<integer, (string|{next:boolean, pattern:boolean, text:string})?>
function M.match_lines(lines, spec)
  local i = 1
  for _, line in ipairs(lines) do
    local s = spec[i]
    if line ~= '' and s and match_spec_elem(line, s) then
      i = i + 1
    end
  end

  if i < #spec + 1 then
    local lines_msg = table.concat(
      --- @param v any
      --- @return string
      vim.tbl_map(function(v)
        return string.format('    - %s', v)
      end, lines),
      '\n'
    )

    error(('Did not match pattern %s with:\n%s'):format(vim.inspect(spec[i]), lines_msg))
  end
end

function M.p(str)
  return { text = str, pattern = true }
end

function M.n(str)
  return { text = str, next = true }
end

function M.np(str)
  return { text = str, pattern = true, next = true }
end

--- @return string[]
function M.debug_messages()
  --- @type string[]
  local r = exec_lua("return require'gitsigns.debug.log'.get(true)")
  for i, line in ipairs(r) do
    -- Remove leading timestamp
    r[i] = line:gsub('^[0-9.]+ D ', '')
  end
  return r
end

--- Like match_debug_messages but elements in spec are unordered
--- @param spec table<integer, (string|{next:boolean, pattern:boolean, text:string})?>
function M.match_dag(spec)
  M.expectf(function()
    local messages = M.debug_messages()
    for _, s in ipairs(spec) do
      M.match_lines(messages, { s })
    end
  end)
end

--- @param spec table<integer, (string|{next:boolean, pattern:boolean, text:string})?>
function M.match_debug_messages(spec)
  M.expectf(function()
    M.match_lines(M.debug_messages(), spec)
  end)
end

function M.setup_path()
  exec_lua(function(path)
    package.path = path
  end, package.path)
end

--- @param group_name? string
function M.enable_lua_treesitter_on_filetype(group_name)
  exec_lua(function(group_name0)
    vim.api.nvim_create_autocmd('FileType', {
      group = vim.api.nvim_create_augroup(group_name0, { clear = true }),
      pattern = 'lua',
      callback = function(args)
        pcall(vim.treesitter.start, args.buf, 'lua')
        local ok, parser = pcall(vim.treesitter.get_parser, args.buf, 'lua')
        if ok and parser then
          pcall(parser.parse, parser, true)
        end
      end,
    })

    vim.cmd('syntax on')
    vim.bo.filetype = 'lua'
  end, group_name or 'gitsigns_test_lua_treesitter')
end

--- @param config? table
--- @param on_attach? boolean
function M.setup_gitsigns(config, on_attach)
  M.setup_path()
  exec_lua(function(config0, on_attach0)
    if config0 and config0.on_attach then
      local maps = config0.on_attach --[[@as [string,string,string][] ]]
      config0.on_attach = function(bufnr)
        for _, map in ipairs(maps) do
          vim.keymap.set(map[1], map[2], map[3], { buffer = bufnr })
        end
      end
    end
    if on_attach0 then
      config0.on_attach = function()
        return false
      end
    end
    require('gitsigns').setup(config0)
    vim.o.diffopt = 'internal,filler,closeoff'
  end, config, on_attach)
end

--- @param status table<string,string|integer>
--- @param bufnr integer
local function check_status(status, bufnr)
  if next(status) == nil then
    eq(false, pcall(buf_get_var, bufnr, 'gitsigns_head'), 'b:gitsigns_head is unexpectedly set')
    eq(
      false,
      pcall(buf_get_var, bufnr, 'gitsigns_status_dict'),
      'b:gitsigns_status_dict is unexpectedly set'
    )
    return
  end

  eq(status.head, buf_get_var(bufnr, 'gitsigns_head'), 'b:gitsigns_head does not match')

  --- @type table<string,string|integer>
  local bstatus = buf_get_var(bufnr, 'gitsigns_status_dict')

  for _, i in ipairs({ 'added', 'changed', 'removed', 'head' }) do
    eq(status[i], bstatus[i], string.format("status['%s'] did not match gitsigns_status_dict", i))
  end
  -- Catch any extra keys
  for i, v in pairs(status) do
    eq(v, bstatus[i], string.format("status['%s'] did not match gitsigns_status_dict", i))
  end
end

--- @param signs table<string,integer>
--- @param bufnr integer
local function check_signs(signs, bufnr)
  local buf_signs = {} --- @type string[]
  local buf_marks = helpers.api.nvim_buf_get_extmarks(bufnr, -1, 0, -1, { details = true })
  for _, s in ipairs(buf_marks) do
    buf_signs[#buf_signs + 1] = assert(s[4]).sign_hl_group
  end

  --- @type table<string,integer>
  local act = {}

  for _, name in ipairs(buf_signs) do
    for t, hl in pairs({
      added = 'GitSignsAdd',
      changed = 'GitSignsChange',
      delete = 'GitSignsDelete',
      changedelete = 'GitSignsChangedelete',
      topdelete = 'GitSignsTopdelete',
      untracked = 'GitSignsUntracked',
    }) do
      if name == hl then
        act[t] = (act[t] or 0) + 1
      end
    end
  end

  eq(signs, act, vim.inspect(buf_signs))
end

--- @param attrs {signs?:table<string,integer>,status?:table<string,string|integer>}
--- @param bufnr? integer
function M.check(attrs, bufnr)
  bufnr = bufnr or 0
  if not attrs then
    return
  end

  M.expectf(function()
    if attrs.status then
      check_status(attrs.status, bufnr)
    end

    if attrs.signs then
      check_signs(attrs.signs, bufnr)
    end
  end)
end

return M
