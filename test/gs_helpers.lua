local helpers = require('test.functional.helpers')()

local system       = helpers.funcs.system
local exec_lua     = helpers.exec_lua
local matches      = helpers.matches
local exec_capture = helpers.exec_capture
local eq           = helpers.eq
local fn           = helpers.funcs
local get_buf_var  = helpers.curbufmeths.get_var

local timeout = 4000

local M = helpers

M.inspect = require('vim.inspect')

M.scratch   = os.getenv('PJ_ROOT')..'/scratch'
M.gitdir    = M.scratch..'/.git'
M.test_file = M.scratch..'/dummy.txt'
M.newfile   = M.scratch.."/newfile.txt"

M.test_config = {
  debug_mode = true,
  signs = {
    add          = {hl = 'DiffAdd'   , text = '+'},
    delete       = {hl = 'DiffDelete', text = '_'},
    change       = {hl = 'DiffChange', text = '~'},
    topdelete    = {hl = 'DiffDelete', text = '^'},
    changedelete = {hl = 'DiffChange', text = '%'},
  },
  keymaps = {
    noremap = true,
    buffer = true,
    ['n mhs'] = '<cmd>lua require"gitsigns".stage_hunk()<CR>',
    ['n mhu'] = '<cmd>lua require"gitsigns".undo_stage_hunk()<CR>',
    ['n mhr'] = '<cmd>lua require"gitsigns".reset_hunk()<CR>',
    ['n mhp'] = '<cmd>lua require"gitsigns".preview_hunk()<CR>',
    ['n mhS'] = '<cmd>lua require"gitsigns".stage_buffer()<CR>',
    ['n mhU'] = '<cmd>lua require"gitsigns".reset_buffer_index()<CR>',
  },
  update_debounce = 5,
}

local test_file_text = {
  'This', 'is', 'a', 'file', 'used', 'for', 'testing', 'gitsigns.', 'The',
  'content', 'doesn\'t', 'matter,', 'it', 'just', 'needs', 'to', 'be', 'static.'
}

function M.git(args)
  system{"git", "-C", M.scratch, unpack(args)}
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
    if pcall(cond) then
      return
    end
    duration = duration + interval
    helpers.sleep(interval)
    interval = interval * 2
  end
  cond()
end

function M.command_fmt(str, ...)
  helpers.command(str:format(...))
end

function M.edit(path)
  M.command_fmt("edit %s", path)
end

function M.write_to_file(path, text)
  local f = io.open(path, 'wb')
  for _, l in ipairs(text) do
    f:write(l)
    f:write('\n')
  end
  f:close()
end

function M.match_lines(lines, spec)
  local i = 1
  for lid, line in ipairs(lines) do
    if line ~= '' then
      local s = spec[i]
      if s then
        if s.pattern then
          matches(s.text, line)
        else
          eq(s, line)
        end
      else
        local extra = {}
        for j=lid,#lines do
          table.insert(extra, lines[j])
        end
        error('Unexpected extra text:\n    '..table.concat(extra, '\n    '))
      end
      i = i + 1
    end
  end
  if i < #spec + 1 then
    local msg = {'lines:'}
    for _, l in ipairs(lines) do
      msg[#msg+1] = string.format(   '"%s"', l)
    end
    error(('Did not match pattern \'%s\' with %s'):format(spec[i], table.concat(msg, '\n')))
  end
end

local function match_lines2(lines, spec)
  local i = 1
  for _, line in ipairs(lines) do
    if line ~= '' then
      local s = spec[i]
      if s then
        if s.pattern then
          if string.match(line, s.text) then
            i = i + 1
          end
        elseif s.next then
          eq(s.text, line)
          i = i + 1
        else
          if s == line then
            i = i + 1
          end
        end
      end
    end
  end

  if i < #spec + 1 then
    local unmatched_msg = table.concat(helpers.tbl_map(function(v)
      return string.format('    - %s', v.text or v)
    end, spec), '\n')

    local lines_msg = table.concat(helpers.tbl_map(function(v)
      return string.format('    - %s', v)
    end, lines), '\n')

    error(('Did not match patterns:\n%s\nwith:\n%s'):format(
      unmatched_msg,
      lines_msg
    ))
  end
end

function M.p(str)
  return {text=str, pattern=true}
end

function M.n(str)
  return {text=str, next=true}
end

function M.debug_messages()
  return exec_lua("return require'gitsigns'.debug_messages(true)")
end

function M.match_dag(lines, spec)
  for _, s in ipairs(spec) do
    match_lines2(lines, {s})
  end
end

function M.match_debug_messages(spec)
  M.expectf(function()
    M.match_lines(M.debug_messages(), spec)
  end)
end

function M.setup_gitsigns(config, extra)
  extra = extra or ''
  exec_lua([[
      local config = ...
    ]]..extra..[[
      require('gitsigns').setup(...)
    ]], config)
  M.expectf(function()
    exec_capture('au gitsigns')
  end)
end

local id = 0
M.it = function(it)
  return function(name, test)
    id = id+1
    return it(name..' #'..id..'#', test)
  end
end

function M.check(attrs, interval)
  attrs = attrs or {}
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
        end
      end

      eq(signs, act, M.inspect(buf_signs))
    end
  end, interval)
end

return M
