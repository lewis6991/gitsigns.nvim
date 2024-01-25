local helpers = require('test.helpers')

local timeout = 8000

local M = helpers

local exec_lua = helpers.exec_lua
local matches = helpers.matches
local eq = helpers.eq
local buf_get_var = helpers.api.nvim_buf_get_var
local system = helpers.fn.system

M.scratch = os.getenv('PJ_ROOT') .. '/scratch'
M.gitdir = M.scratch .. '/.git'
M.test_file = M.scratch .. '/dummy.txt'
M.newfile = M.scratch .. '/newfile.txt'

local extmark_signs = os.getenv('NVIM_TEST_VERSION') ~= 'v0.8.3'

M.test_config = {
  debug_mode = true,
  _test_mode = true,
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
  _extmark_signs = extmark_signs,
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
function M.gitf(args)
  system({ 'git', '-C', M.scratch, unpack(args) })
end

--- @param cmds string[][]
function M.gitm(cmds)
  for _, cmd in ipairs(cmds) do
    M.gitf(cmd)
  end
  helpers.sleep(10)
end

--- Run a git command and add a delay
function M.git(args)
  M.gitf(args)
  helpers.sleep(10)
end

function M.cleanup()
  system({ 'rm', '-rf', M.scratch })
end

function M.setup_git()
  M.gitf({ 'init', '-b', 'master' })

  -- Always force color to test settings don't interfere with gitsigns systems
  -- commands (addresses #23)
  M.gitf({ 'config', 'color.branch', 'always' })
  M.gitf({ 'config', 'color.ui', 'always' })
  M.gitf({ 'config', 'color.diff', 'always' })
  M.gitf({ 'config', 'color.interactive', 'always' })
  M.gitf({ 'config', 'color.status', 'always' })
  M.gitf({ 'config', 'color.grep', 'always' })
  M.gitf({ 'config', 'color.pager', 'true' })
  M.gitf({ 'config', 'color.decorate', 'always' })
  M.gitf({ 'config', 'color.showbranch', 'always' })

  M.gitf({ 'config', 'merge.conflictStyle', 'merge' })

  M.gitf({ 'config', 'user.email', 'tester@com.com' })
  M.gitf({ 'config', 'user.name', 'tester' })

  M.gitf({ 'config', 'init.defaultBranch', 'master' })
end

--- Setup a basic git repository in directory `helpers.scratch` with a single file
--- `helpers.test_file` committed.
--- @param opts? {test_file_text?: string[], no_add?: boolean}
function M.setup_test_repo(opts)
  local text = opts and opts.test_file_text or test_file_text
  M.cleanup()
  system({ 'mkdir', M.scratch })
  M.setup_git()
  system({ 'touch', M.test_file })
  M.write_to_file(M.test_file, text)
  if not (opts and opts.no_add) then
    M.gitf({ 'add', M.test_file })
    M.gitf({ 'commit', '-m', 'init commit' })
  end
  helpers.sleep(20)
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
    interval = interval * 2
  end
  cond()
end

function M.edit(path)
  helpers.api.nvim_command('edit ' .. path)
end

--- @param path string
--- @param text string[]
function M.write_to_file(path, text)
  local f = assert(io.open(path, 'wb'))
  for _, l in ipairs(text) do
    f:write(l)
    f:write('\n')
  end
  f:close()
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
    local unmatched_msg = table.concat(
      vim.tbl_map(function(v)
        return string.format('    - %s', v.text or v)
      end, spec),
      '\n'
    )

    local lines_msg = table.concat(
      vim.tbl_map(function(v)
        return string.format('    - %s', v)
      end, lines),
      '\n'
    )

    error(('Did not match patterns:\n%s\nwith:\n%s'):format(unmatched_msg, lines_msg))
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
  return exec_lua("return require'gitsigns.debug.log'.messages")
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

function M.setup_gitsigns(config, on_attach)
  exec_lua(
    [[
      local config, on_attach = ...
      if config and config.on_attach then
        local maps = config.on_attach
        config.on_attach = function(bufnr)
          for _, map in ipairs(maps) do
            vim.keymap.set(map[1], map[2], map[3], {buffer = bufnr})
          end
        end
      end
      if on_attach then
        config.on_attach = function()
          return false
        end
      end
      require('gitsigns').setup(config)
    ]],
    config,
    on_attach
  )
  M.expectf(function()
    return exec_lua([[return require'gitsigns'._setup_done == true]])
  end)
end

--- @param status table<string,string|integer>
local function check_status(status)
  local fn = helpers.fn
  if next(status) == nil then
    eq(0, fn.exists('b:gitsigns_head'), 'b:gitsigns_head is unexpectedly set')
    eq(0, fn.exists('b:gitsigns_status_dict'), 'b:gitsigns_status_dict is unexpectedly set')
  else
    eq(1, fn.exists('b:gitsigns_head'), 'b:gitsigns_head is not set')
    eq(status.head, buf_get_var(0, 'gitsigns_head'), 'b:gitsigns_head does not match')

    --- @type table<string,string|integer>
    local bstatus = buf_get_var(0, 'gitsigns_status_dict')

    for _, i in ipairs({ 'added', 'changed', 'removed', 'head' }) do
      eq(status[i], bstatus[i], string.format("status['%s'] did not match gitsigns_status_dict", i))
    end
    -- Catch any extra keys
    for i, v in pairs(status) do
      eq(v, bstatus[i], string.format("status['%s'] did not match gitsigns_status_dict", i))
    end
  end
end

--- @param signs table<string,integer>
--- @param extmarks boolean
local function check_signs(signs, extmarks)
  local buf_signs = {} --- @type string[]
  if extmarks then
    local buf_marks = helpers.api.nvim_buf_get_extmarks(0, -1, 0, -1, { details = true })
    for _, s in ipairs(buf_marks) do
      buf_signs[#buf_signs + 1] = s[4].sign_hl_group
    end
  else
    local buf_vimsigns = helpers.fn.sign_getplaced('%', { group = '*' })[1].signs
    for _, s in ipairs(buf_vimsigns) do
      buf_signs[#buf_signs + 1] = s.name
    end
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

--- @param attrs {signs:table<string,integer>,status:table<string,string|integer>}
--- @param interval? integer
function M.check(attrs, interval)
  if not attrs then
    return
  end

  local status = attrs.status
  local signs = attrs.signs

  M.expectf(function()
    if status then
      check_status(status)
    end

    if signs then
      check_signs(signs, extmark_signs)
    end
  end, interval)
end

return M
