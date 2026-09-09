local async = require('gitsigns.async')
local cache = require('gitsigns.cache').cache
local diffthis = require('gitsigns.actions.diffthis')
local message = require('gitsigns.message')
local Repo = require('gitsigns.git.repo')

local api = vim.api
local fn = vim.fn
local uv = vim.uv or vim.loop ---@diagnostic disable-line: deprecated
local ns = api.nvim_create_namespace('gitsigns_diff')
local ns_selection = api.nvim_create_namespace('gitsigns_diff_selection')

local HIGHLIGHTS = {
  A = 'GitSignsAdd',
  D = 'GitSignsDelete',
  M = 'GitSignsChange',
  ['?'] = 'GitSignsUntracked',
}

local MODES = {
  missing = '000000',
  symlink = '120000',
  gitlink = '160000',
}

--- Bind file navigation while a diff window is current, restoring mappings on leave.
--- Shared buffers then use their normal mappings in every other window or panel.
--- @param panel integer
--- @param windows Gitsigns.DiffWindows
--- @param navigate fun(count: integer)
--- @return fun() cleanup
local function setup_navigation(panel, windows, navigate)
  local group = api.nvim_create_augroup('gitsigns_diff_' .. panel, {})
  local restore = {} --- @type fun()[]
  local mapped_win --- @type integer?
  local directions = { [']f'] = 1, ['[f'] = -1 } --- @type table<string, integer>

  --- Restore this window's mappings before entering another buffer or window.
  local function unmap()
    for _, undo in ipairs(restore) do
      undo()
    end
    restore = {}
    mapped_win = nil
  end

  api.nvim_create_autocmd({ 'BufLeave', 'WinLeave' }, {
    group = group,
    callback = function()
      -- Buffer operations in another window must not remove the current mappings.
      if api.nvim_get_current_win() == mapped_win then
        unmap()
      end
    end,
  })
  api.nvim_create_autocmd({ 'BufEnter', 'WinEnter' }, {
    group = group,
    callback = function()
      local win = api.nvim_get_current_win()
      if
        #restore > 0
        or not windows.left
        or not api.nvim_win_is_valid(windows.left)
        or (win ~= windows.left and win ~= windows.right)
      then
        return
      end
      local buf = api.nvim_get_current_buf()
      mapped_win = win
      for key, direction in pairs(directions) do
        local previous = fn.maparg(key, 'n', false, true)
        local callback = function()
          navigate(direction * vim.v.count1)
        end
        vim.keymap.set('n', key, callback, {
          buffer = buf,
          desc = direction == 1 and 'Next file' or 'Previous file',
        })
        restore[#restore + 1] = function()
          if not api.nvim_buf_is_valid(buf) then
            return
          end
          api.nvim_buf_call(buf, function()
            -- Leave a mapping installed by the user after entering the window alone.
            if fn.maparg(key, 'n', false, true).callback == callback then
              vim.keymap.del('n', key, { buffer = buf })
              if previous.buffer == 1 then
                fn.mapset('n', false, previous)
              end
            end
          end)
        end
      end
    end,
  })

  return function()
    api.nvim_del_augroup_by_id(group)
    unmap()
  end
end

--- Get one side of a file diff, reusing working buffers to preserve unsaved edits.
--- Missing files, gitlinks, and working-tree symlinks use scratch buffers.
--- @async
--- @param repo Gitsigns.Repo
--- @param revision string? Nil selects the working tree for the target side.
--- @param entry Gitsigns.DiffEntry
--- @param old boolean Use the entry's base path and mode.
--- @return integer? bufnr
--- @return boolean? created Whether this call created a disposable buffer.
local function file_buffer(repo, revision, entry, old)
  local mode = old and entry.old_mode or entry.mode
  local path = old and (entry.oldpath or entry.path) or entry.path
  local worktree = not old and not revision
  local symlink = worktree and mode == MODES.symlink

  if mode ~= MODES.missing and mode ~= MODES.gitlink and not symlink then
    if worktree then
      local buf = fn.bufadd(repo.toplevel .. '/' .. path)
      fn.bufload(buf)
      vim.bo[buf].buflisted = true
      return buf, false
    end
    local _, bufnr, created = diffthis.create_revision_buf(repo, assert(revision), path)
    return bufnr, created
  end

  local text = {} --- @type string[]

  -- Submodules appear in Git's file list as gitlinks (mode 160000). Represent
  -- each side as a "Subproject commit <oid>" line so Neovim's file diff shows
  -- which commit the submodule moved from and to.
  if mode == MODES.gitlink then
    local oid = old and entry.old_oid or entry.oid
    if worktree then
      local subrepo = Repo.get(repo.toplevel .. '/' .. path)
      if subrepo then
        if subrepo.toplevel == repo.toplevel .. '/' .. path then
          local head, _, code = subrepo:command(
            { 'rev-parse', '--verify', 'HEAD' },
            { ignore_error = true }
          )
          oid = code == 0 and assert(head[1]) or '(unborn)'
        end
        subrepo:unref()
      end
    end
    text = { 'Subproject commit ' .. oid }
  elseif symlink then
    -- Git compares the link target, not the contents of the file it points to.
    text = vim.split(assert(uv.fs_readlink(repo.toplevel .. '/' .. path)), '\n', { plain = true })
  end

  local bufnr = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(bufnr, 0, -1, false, text)
  vim.bo[bufnr].bufhidden = 'wipe'
  vim.bo[bufnr].modifiable = false
  return bufnr, true
end

--- Delete a buffer created for an abandoned read, provided no window displays it.
--- @param buf integer?
--- @param created boolean?
local function discard(buf, created)
  if buf and created and api.nvim_buf_is_valid(buf) and #fn.win_findbuf(buf) == 0 then
    api.nvim_buf_delete(buf, { force = true })
  end
end

--- Render the file tree and configure its window, sorting entries in place by path.
--- @param panel_win integer
--- @param revision string?
--- @param entries Gitsigns.DiffEntry[]
--- @param commit string[]?
--- @return integer[] file_lnums Panel line numbers in the sorted entry order.
local function render_panel(panel_win, revision, entries, commit)
  local panel = api.nvim_win_get_buf(panel_win)
  local lines = {
    commit and fn.strtrans(assert(commit[1]))
      or 'Diff: ' .. fn.strtrans(revision or 'working tree'),
    'g? help  <CR> open/fold  q close',
    '',
  }

  local directories = {} --- @type table<string, integer>
  local file_lnums = {} --- @type integer[]

  -- Sorting keeps each directory's descendants contiguous, giving it one fold range.
  table.sort(entries, function(a, b)
    return a.path < b.path
  end)

  for _, entry in ipairs(entries) do
    local parts = vim.split(entry.path, '/', { plain = true })
    local dir = ''
    for depth = 1, #parts - 1 do
      local name = assert(parts[depth])
      dir = dir .. name .. '/'
      if not directories[dir] then
        -- Escape a leading space so foldexpr sees only the tree's indentation.
        name = fn.strtrans(name):gsub('^ ', '\\ ')
        lines[#lines + 1] = string.rep('  ', depth - 1) .. ' ' .. name .. '/'
        directories[dir] = #lines
      end
    end

    local path = fn.strtrans(parts[#parts])
    if entry.oldpath then
      path = fn.strtrans(entry.oldpath) .. ' -> ' .. path
    end
    lines[#lines + 1] = string.rep('  ', #parts - 1) .. ' ' .. entry.status .. ' ' .. path
    file_lnums[#file_lnums + 1] = #lines
  end

  if #entries == 0 then
    lines[#lines + 1] = 'No changes'
  end

  api.nvim_buf_set_lines(panel, 0, -1, false, lines)

  if commit then
    api.nvim_buf_set_extmark(panel, ns, 0, 0, {
      end_row = 1,
      end_col = 0,
      hl_group = 'Title',
    })
  end

  local has_devicons, devicons = pcall(require, 'nvim-web-devicons')
  for i, lnum in ipairs(file_lnums) do
    local entry = assert(entries[i])
    local col = assert(assert(lines[lnum]):find('%S')) - 1
    local stats = {} --- @type Gitsigns.VirtTextChunk[]
    if not entry.added then
      stats[1] = { 'Bin', 'Comment' }
    elseif entry.added > 0 then
      stats[1] = { '+' .. entry.added, 'GitSignsAdd' }
    end
    if entry.removed and entry.removed > 0 then
      stats[#stats + 1] = {
        (#stats > 0 and ' -' or '-') .. entry.removed,
        'GitSignsDelete',
      }
    end
    api.nvim_buf_set_extmark(panel, ns, lnum - 1, col, {
      end_col = col + 1,
      hl_group = HIGHLIGHTS[entry.status] or 'GitSignsChange',
      virt_text = stats,
      virt_text_pos = 'right_align',
      hl_mode = 'combine',
    })
    if has_devicons then
      local icon, hl = devicons.get_icon(fn.fnamemodify(entry.path, ':t'), nil, { default = true })
      if icon then
        -- Place icons after the status without changing the tree's text or indentation.
        api.nvim_buf_set_extmark(panel, ns, lnum - 1, col + 2, {
          virt_text = { { icon .. ' ', hl } },
          virt_text_pos = 'inline',
          hl_mode = 'combine',
        })
      end
    end
  end

  vim.bo[panel].bufhidden = 'wipe'
  vim.bo[panel].modifiable = false
  vim.bo[panel].filetype = 'gitsigns-diff'

  local wo = vim.wo[panel_win][0]
  wo.number = false
  wo.relativenumber = false
  wo.signcolumn = 'no'
  wo.foldcolumn = '0'
  -- Each tree level adds two spaces. Start a separate fold at each parent row,
  -- including adjacent parents at the same depth, and leave the header unfolded.
  wo.foldexpr = 'v:lnum <= 3 ? 0 : indent(v:lnum + 1) > indent(v:lnum)'
    .. ' ? ">" . (indent(v:lnum + 1) / 2) : indent(v:lnum) / 2'
  wo.foldmethod = 'expr'
  wo.foldminlines = 0
  wo.wrap = false
  wo.spell = false
  wo.list = false
  wo.cursorline = true
  wo.winfixbuf = true
  wo.winfixwidth = true

  --- @diagnostic disable-next-line: deprecated
  api.nvim_win_set_width(panel_win, 36)
  for _, lnum in pairs(directories) do
    local col = assert(assert(lines[lnum]):find('%S')) - 1
    api.nvim_buf_set_extmark(panel, ns, lnum - 1, col, {
      end_row = lnum,
      end_col = 0,
      hl_group = 'Directory',
      -- Devicons supplies file icons; use a Nerd Font folder for directories.
      virt_text = has_devicons and { { ' ', 'Directory' } } or nil,
      virt_text_pos = 'inline',
      hl_mode = 'combine',
    })
  end
  wo.foldenable = true
  vim.cmd('normal! zR')
  api.nvim_win_set_cursor(panel_win, { file_lnums[1] or (commit and 1 or 4), 0 })

  return file_lnums
end

--- @class Gitsigns.DiffWindows
--- @field panel integer
--- @field right integer
--- @field left integer?

--- Show a commit message or file diff beside the panel, recreating closed splits.
--- Disable the previous diff before switching buffers and update window IDs in place.
--- @param windows Gitsigns.DiffWindows
--- @param buf integer
--- @param base_buf integer? Omit to show only the commit message.
local function show_buffers(windows, buf, base_buf)
  -- Hidden buffers keep participating in the diff unless removed before switching.
  for _, win in ipairs({ windows.right, windows.left }) do
    if api.nvim_win_is_valid(win) then
      vim.wo[win].diff = false
    end
  end

  if not base_buf then
    if windows.left and api.nvim_win_is_valid(windows.left) then
      api.nvim_win_close(windows.left, false)
    end
    windows.left = nil
  end

  if not api.nvim_win_is_valid(windows.right) then
    api.nvim_set_current_win(windows.panel)
    vim.cmd.vsplit({ mods = { split = 'botright', keepalt = true } })
    windows.right = api.nvim_get_current_win()
  end

  api.nvim_win_set_buf(windows.right, buf)
  api.nvim_set_current_win(windows.right)
  if not base_buf then
    return
  end

  if not windows.left or not api.nvim_win_is_valid(windows.left) then
    vim.cmd.vsplit({ mods = { split = 'aboveleft', keepalt = true } })
    windows.left = api.nvim_get_current_win()
  end
  api.nvim_win_set_buf(windows.left, base_buf)
  for _, win in ipairs({ windows.left, windows.right }) do
    api.nvim_win_call(win, function()
      vim.cmd.diffthis()
      vim.cmd('normal! gg')
    end)
  end
  api.nvim_set_current_win(windows.right)
  vim.cmd.diffupdate()
end

--- Show panel and diff-buffer mappings in a focused popup.
--- @param panel integer
local function show_help(panel)
  local popup = require('gitsigns.popup')
  popup.close('diff_help')
  local lines = { { { 'File panel', 'Title' } } } --- @type Gitsigns.LineSpec[]
  for _, map in ipairs(api.nvim_buf_get_keymap(panel, 'n')) do
    lines[#lines + 1] = { { ('%-8s %s'):format(map.lhs, map.desc or map.rhs), 'Normal' } }
  end
  vim.list_extend(lines, {
    { { '', 'Normal' } },
    { { 'Diff buffers', 'Title' } },
    { { ']f / [f  Next / previous file (accepts count)', 'Normal' } },
    { { ']c / [c  Next / previous change', 'Normal' } },
    { { '', 'Normal' } },
    { { 'q / <Esc> / g?  Close this help', 'Comment' } },
  })
  local win, buf =
    popup.create(lines, require('gitsigns.config').config.preview_config, 'diff_help')
  for _, key in ipairs({ '<Esc>', 'g?' }) do
    vim.keymap.set('n', key, '<cmd>close<CR>', { buffer = buf, silent = true })
  end
  api.nvim_set_current_win(win)
end

--- Bind panel actions for files, directory folds, commit metadata, and help.
--- @param open fun(how: 'diff'|'target'|'base', keep_focus?: boolean)
--- @param panel_buf integer
--- @param panel_win integer
local function setup_keymaps(open, panel_buf, panel_win)
  --- Bind a normal-mode action to the panel buffer with its description.
  --- @param key string
  --- @param desc string
  --- @param callback fun()
  local function map(key, desc, callback)
    vim.keymap.set('n', key, callback, { buffer = panel_buf, desc = desc })
  end

  map('<CR>', 'Open file, show commit message, or toggle directory fold', function()
    local lnum = api.nvim_win_get_cursor(panel_win)[1]
    if lnum > 3 and fn.indent(lnum + 1) > fn.indent(lnum) then
      vim.cmd('normal! za')
    else
      async.run(open, 'diff'):raise_on_error()
    end
  end)

  map('<S-CR>', 'Diff file and keep focus in the panel', function()
    async.run(open, 'diff', true):raise_on_error()
  end)

  map('o', 'View target file (tab)', function()
    async.run(open, 'target'):raise_on_error()
  end)

  map('O', 'View file at base revision (tab)', function()
    async.run(open, 'base'):raise_on_error()
  end)

  map('g?', 'Show available keys', function()
    show_help(panel_buf)
  end)

  map('q', 'Close diff', function()
    -- Leave an empty tab when the diff reused the startup window.
    if #api.nvim_list_tabpages() == 1 then
      vim.cmd.tabnew()
      vim.cmd.tabprevious()
    end
    vim.cmd.tabclose()
  end)
end

--- Find the current buffer's repository, falling back to its directory or cwd.
--- The caller owns the returned reference and must release it with unref().
--- @async
--- @return Gitsigns.Repo? repo
--- @return string? err
local function get_repo()
  local bcache = cache[api.nvim_get_current_buf()]
  if bcache then
    return bcache.git_obj.repo:ref()
  end

  local name = api.nvim_buf_get_name(0)
  local dir = vim.bo.buftype == '' and name ~= '' and vim.fs.dirname(name) or nil
  return Repo.get(dir)
end

--- Open a repository diff panel and display its first file, reusing an empty startup window.
--- @async
--- @param revision? string Commit or revision range; nil compares HEAD with the working tree.
--- @param paths? string[] Git pathspecs, relative to the current directory in the repository.
return function(revision, paths)
  local source_win = api.nvim_get_current_win()
  local cwd = fn.getcwd()
  local repo, err = get_repo()
  if not repo then
    message.error(err or 'Not in a Git repository')
    return
  end

  local ok, base, target, entries, commit =
    pcall(require('gitsigns.git.diff'), repo, revision, paths, cwd)
  if not ok then
    repo:unref()
    message.error(base or 'Unable to read revision')
    return
  end

  if api.nvim_get_current_win() ~= source_win then
    repo:unref()
    return
  end

  if
    #api.nvim_list_tabpages() > 1
    or fn.winlayout()[1] ~= 'leaf' -- Floating UI does not count as an existing split.
    or api.nvim_buf_get_name(0) ~= ''
    or vim.bo.buftype ~= ''
    or vim.bo.modified
    or api.nvim_buf_line_count(0) > 1
    or fn.getline(1) ~= ''
  then
    vim.cmd.tabnew()
  end
  local tab = api.nvim_get_current_tabpage()
  local right_win = api.nvim_get_current_win()
  vim.bo.bufhidden = 'wipe'

  vim.cmd.vsplit({ mods = { split = 'topleft', keepalt = true } })
  local panel_win = api.nvim_get_current_win()
  local windows = { panel = panel_win, right = right_win } --- @type Gitsigns.DiffWindows
  local panel = api.nvim_create_buf(false, true)
  api.nvim_win_set_buf(panel_win, panel)
  api.nvim_buf_set_name(panel, ('gitsigns-diff://%s//%d'):format(repo.gitdir, tab))

  local file_lnums = render_panel(panel_win, revision, entries, commit)
  local current_file = 1

  --- Open the selected commit message, file diff, or one side in a new tab.
  --- Discard newly created buffers if the panel closes or the user changes tabs during a read.
  --- @async
  --- @param how 'diff'|'target'|'base'
  local function open_file(how)
    local lnum = api.nvim_win_get_cursor(panel_win)[1]
    if lnum == 1 and commit and how == 'diff' then
      local buf = require('gitsigns.actions.show_commit').create_buf(repo, assert(target), commit)
      show_buffers(windows, buf)
      api.nvim_buf_clear_namespace(panel, ns_selection, 0, -1)
      return
    end

    local index = fn.index(file_lnums, lnum) + 1
    local entry = entries[index]
    if not entry then
      return
    end

    local old = how == 'base'
    local buf, created = file_buffer(repo, old and base or target, entry, old)
    local old_buf, old_created
    if buf and how == 'diff' then
      old_buf, old_created = file_buffer(repo, base, entry, true)
    end
    if
      not buf
      or (how == 'diff' and not old_buf)
      or not api.nvim_win_is_valid(panel_win)
      or api.nvim_get_current_tabpage() ~= tab
    then
      discard(buf, created)
      discard(old_buf, old_created)
      return
    end

    if how == 'diff' then
      show_buffers(windows, buf, old_buf)
      current_file = index
      local line = assert(api.nvim_buf_get_lines(panel, lnum - 1, lnum, false)[1])
      -- Skip the indentation, status letter, and its separator.
      local col = assert(line:find('%S')) + 1
      api.nvim_buf_set_extmark(panel, ns_selection, lnum - 1, col, {
        id = 1, -- Move the panel's single selection mark after a successful open.
        end_col = #line,
        hl_group = 'QuickFixLine',
        priority = 50, -- Preserve file icon colors above the filename highlight.
      })
    else
      vim.cmd.tabnew()
      api.nvim_win_set_buf(0, buf)
    end
  end

  local busy = false
  --- Ignore overlapping opens; retain the repository during reads and report errors.
  --- @async
  --- @param how 'diff'|'target'|'base'
  --- @param keep_focus? boolean
  local function open(how, keep_focus)
    if busy then
      return
    end
    busy = true
    local focus_win = api.nvim_get_current_win()
    -- Keep the repository alive if the panel is closed while Git is reading a file.
    repo:ref()
    local opened, open_err = pcall(open_file, how)
    repo:unref()
    busy = false
    if
      keep_focus
      and api.nvim_win_is_valid(focus_win)
      and api.nvim_get_current_tabpage() == tab
    then
      api.nvim_set_current_win(focus_win)
    end
    if not opened then
      message.error(open_err)
    end
  end

  --- Move through this panel's files while keeping focus in the current diff window.
  --- @param count integer Signed file offset, clamped to the first and last entries.
  local unmap = setup_navigation(panel, windows, function(count)
    if busy then
      return
    end

    local next_file = math.max(1, math.min(#file_lnums, current_file + count))
    if next_file == current_file then
      return
    end

    api.nvim_win_call(panel_win, function()
      api.nvim_win_set_cursor(panel_win, { assert(file_lnums[next_file]), 0 })
      vim.cmd('normal! zv')
    end)

    async.run(open, 'diff', true):raise_on_error()
  end)

  api.nvim_create_autocmd('BufWipeout', {
    buffer = panel,
    once = true,
    callback = function()
      unmap()
      repo:unref()
    end,
  })

  setup_keymaps(open, panel, panel_win)

  if #entries > 0 then
    open('diff', true)
  end
end
