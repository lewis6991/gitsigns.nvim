local helpers = require('test.functional.helpers')(nil)

local system   = helpers.funcs.system
local exec_lua = helpers.exec_lua
local matches  = helpers.matches
local exec_capture = helpers.exec_capture
local eq       = helpers.eq

local timeout = 4000

local M = helpers

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
  M.git{"init"}

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

function M.init(no_add)
  M.cleanup()
  system{"mkdir", M.scratch}
  M.setup_git()
  system{"touch", M.test_file}
  M.write_to_file(M.test_file, test_file_text)
  if not no_add then
    M.git{"add", M.test_file}
    M.git{"commit", "-m", "init commit"}
  end
end

function M.wait(cond)
  local duration = 0
  local interval = 5
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
    -- print('Lines:')
    -- for _, l in ipairs(lines) do
    --   print(string.format(   '"%s"', l))
    -- end
    error(('Did not match pattern \'%s\''):format(spec[i]))
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
    local unmatched = {}
    for j = i, #spec do
      table.insert(unmatched, spec[j].text or spec[j])
    end
    error(('Did not match patterns:\n    - %s'):format(table.concat(unmatched, '\n    - ')))
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
  M.wait(function()
    M.match_lines(M.debug_messages(), spec)
  end)
end

function M.setup(config)
  exec_lua([[require('gitsigns').setup(...)]], config)
  M.wait(function()
    exec_capture('au gitsigns')
  end)
end

local id = 0
M.it = function(it)
  return function(name, test)
    id = id+1
    return it(name..' #'..id, test)
  end
end

return M
