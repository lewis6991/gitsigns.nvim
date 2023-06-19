local helpers = require'test.helpers'

local timeout = 8000

local M = helpers

local exec_lua = helpers.exec_lua
local matches = helpers.matches
local eq = helpers.eq
local get_buf_var = helpers.curbufmeths.get_var
local system = helpers.funcs.system

M.scratch   = os.getenv('PJ_ROOT')..'/scratch'
M.gitdir    = M.scratch..'/.git'
M.test_file = M.scratch..'/dummy.txt'
M.newfile   = M.scratch.."/newfile.txt"

M.test_config = {
  debug_mode = true,
  _test_mode = true,
  signs = {
    add          = {hl = 'DiffAdd'   , text = '+'},
    delete       = {hl = 'DiffDelete', text = '_'},
    change       = {hl = 'DiffChange', text = '~'},
    topdelete    = {hl = 'DiffDelete', text = '^'},
    changedelete = {hl = 'DiffChange', text = '%'},
    untracked    = {hl = 'DiffChange', text = '#'},
  },
  on_attach = {
    {'n', 'mhs', '<cmd>lua require"gitsigns".stage_hunk()<CR>'},
    {'n', 'mhu', '<cmd>lua require"gitsigns".undo_stage_hunk()<CR>'},
    {'n', 'mhr', '<cmd>lua require"gitsigns".reset_hunk()<CR>'},
    {'n', 'mhp', '<cmd>lua require"gitsigns".preview_hunk()<CR>'},
    {'n', 'mhS', '<cmd>lua require"gitsigns".stage_buffer()<CR>'},
    {'n', 'mhU', '<cmd>lua require"gitsigns".reset_buffer_index()<CR>'},
  },
  update_debounce = 5,
}

local test_file_text = {
  'This', 'is', 'a', 'file', 'used', 'for', 'testing', 'gitsigns.', 'The',
  'content', 'doesn\'t', 'matter,', 'it', 'just', 'needs', 'to', 'be', 'static.'
}

function M.git(args)
  exec_lua("vim.loop.sleep(20)")
  system{"git", "-C", M.scratch, unpack(args)}
  exec_lua("vim.loop.sleep(20)")
end

function M.cleanup()
  system{"rm", "-rf", M.scratch}
end

function M.setup_git()
  M.git{"init", '-b', 'master'}

  -- Always force color to test settings don't interfere with gitsigns systems
  -- commands (addresses #23)
  M.git{'config', 'color.branch'     , 'always'}
  M.git{'config', 'color.ui'         , 'always'}
  M.git{'config', 'color.diff'       , 'always'}
  M.git{'config', 'color.interactive', 'always'}
  M.git{'config', 'color.status'     , 'always'}
  M.git{'config', 'color.grep'       , 'always'}
  M.git{'config', 'color.pager'      , 'true'}
  M.git{'config', 'color.decorate'   , 'always'}
  M.git{'config', 'color.showbranch' , 'always'}

  M.git{'config', 'merge.conflictStyle', 'merge'}

  M.git{'config', 'user.email', 'tester@com.com'}
  M.git{'config', 'user.name' , 'tester'}

  M.git{'config', 'init.defaultBranch', 'master'}
end

function M.setup_test_repo(opts)
  local text = opts and opts.test_file_text or test_file_text
  M.cleanup()
  system{"mkdir", M.scratch}
  M.setup_git()
  system{"touch", M.test_file}
  M.write_to_file(M.test_file, text)
  if not (opts and opts.no_add) then
    M.git{"add", M.test_file}
    M.git{"commit", "-m", "init commit"}
  end
end

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
  helpers.command("edit " .. path)
end

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
    local unmatched_msg = table.concat(vim.tbl_map(function(v)
      return string.format('    - %s', v.text or v)
    end, spec), '\n')

    local lines_msg = table.concat(vim.tbl_map(function(v)
      return string.format('    - %s', v)
    end, lines), '\n')

    error(('Did not match patterns:\n%s\nwith:\n%s'):format(
      unmatched_msg,
      lines_msg
    ))
  end
end

function M.p(str)
  return {text = str, pattern = true}
end

function M.n(str)
  return {text = str, next = true}
end

function M.np(str)
  return {text = str, pattern = true, next = true}
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
      M.match_lines(messages, {s})
    end
  end)
end

--- @param spec table<integer, (string|{next:boolean, pattern:boolean, text:string})?>
function M.match_debug_messages(spec)
  M.expectf(function()
    M.match_lines(M.debug_messages(), spec)
  end)
end

function M.setup_gitsigns(config, extra)
  extra = extra or ''
  exec_lua([[
      local config = ...
      if config and config.on_attach then
        local maps = config.on_attach
        config.on_attach = function(bufnr)
          for _, map in ipairs(maps) do
            vim.keymap.set(map[1], map[2], map[3], {buffer = bufnr})
          end
        end
      end
    ]]..extra..[[
      require('gitsigns').setup(...)
    ]], config)
  M.expectf(function()
    return exec_lua[[return require'gitsigns'._setup_done == true]]
  end)
end

function M.check(attrs, interval)
  attrs = attrs or {}
  local fn = helpers.funcs

  M.expectf(function()
    local status = attrs.status
    local signs  = attrs.signs

    if status then
      if next(status) == nil then
        eq(0, fn.exists('b:gitsigns_head'),
          'b:gitsigns_head is unexpectedly set')
        eq(0, fn.exists('b:gitsigns_status_dict'),
          'b:gitsigns_status_dict is unexpectedly set')
      else
        eq(1, fn.exists('b:gitsigns_head'),
          'b:gitsigns_head is not set')
        eq(status.head, get_buf_var('gitsigns_head'),
          'b:gitsigns_head does not match')

        local bstatus = get_buf_var("gitsigns_status_dict")

        for _, i in ipairs{'added', 'changed', 'removed', 'head'} do
          eq(status[i], bstatus[i],
            string.format("status['%s'] did not match gitsigns_status_dict", i))
        end
        -- Catch any extra keys
        for i, v in pairs(status) do
          eq(v, bstatus[i],
            string.format("status['%s'] did not match gitsigns_status_dict", i))
        end
      end
    end

    if signs then
      local act = {
        added        = 0,
        changed      = 0,
        delete       = 0,
        changedelete = 0,
        topdelete    = 0,
        untracked    = 0,
      }

      for k, _ in pairs(act) do
        signs[k] = signs[k] or 0
      end

      local buf_signs = fn.sign_getplaced("%", {group='*'})[1].signs

      for _, s in ipairs(buf_signs) do
        if     s.name == "GitSignsAdd"          then act.added        = act.added   + 1
        elseif s.name == "GitSignsChange"       then act.changed      = act.changed + 1
        elseif s.name == "GitSignsDelete"       then act.delete       = act.delete + 1
        elseif s.name == "GitSignsChangedelete" then act.changedelete = act.changedelete + 1
        elseif s.name == "GitSignsTopdelete"    then act.topdelete    = act.topdelete + 1
        elseif s.name == "GitSignsUntracked"    then act.untracked    = act.untracked + 1
        end
      end

      eq(signs, act, vim.inspect(buf_signs))
    end
  end, interval)
end

return M
