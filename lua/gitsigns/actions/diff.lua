local async = require('gitsigns.async')
local cache = require('gitsigns.cache').cache
local diffthis = require('gitsigns.actions.diffthis')
local git_diff = require('gitsigns.git.diff')
local message = require('gitsigns.message')
local Repo = require('gitsigns.git.repo')

local api = vim.api
local fn = vim.fn
local uv = vim.uv or vim.loop ---@diagnostic disable-line: deprecated
local ns = api.nvim_create_namespace('gitsigns_diff')
local ns_selection = api.nvim_create_namespace('gitsigns_diff_selection')
local ns_header = api.nvim_create_namespace('gitsigns_diff_header')

--- @class Gitsigns.DiffBufferRef
--- @field refs integer
--- @field bufhidden ''|'hide'|'unload'|'delete'|'wipe'
--- @field loaded boolean
--- @field created boolean

-- Buffers can belong to more than one review panel.
local buffer_refs = {} --- @type table<integer, Gitsigns.DiffBufferRef>

local HIGHLIGHTS = {
  A = 'GitSignsAdd',
  D = 'GitSignsDelete',
  M = 'GitSignsChange',
  ['?'] = 'GitSignsUntracked',
  [' '] = 'Comment',
}

local MODES = {
  missing = '000000',
  symlink = '120000',
  gitlink = '160000',
}

--- Delete a buffer created for an abandoned read, provided no window displays it.
--- @param buf integer?
--- @param created boolean?
local function discard(buf, created)
  if buf and created and api.nvim_buf_is_valid(buf) and #fn.win_findbuf(buf) == 0 then
    api.nvim_buf_delete(buf, { force = true })
  end
end

--- @param added integer?
--- @param removed integer?
--- @param binary? boolean
--- @return Gitsigns.VirtTextChunk[]
local function diffstat(added, removed, binary)
  local stats = {} --- @type Gitsigns.VirtTextChunk[]
  if added and added > 0 then
    stats[1] = { '+' .. added, 'GitSignsAdd' }
  end

  if removed and removed > 0 then
    stats[#stats + 1] = { (#stats > 0 and ' -' or '-') .. removed, 'GitSignsDelete' }
  end

  if not added or binary then
    stats[#stats + 1] = { (#stats > 0 and ' ' or '') .. 'Bin', 'Comment' }
  end

  return stats
end

--- @class Gitsigns.DiffNode
--- @field path string
--- @field lnum integer
--- @field first integer First entry in the sorted file list.
--- @field last integer Last entry; equal to first for a file.
--- @field directory? boolean

--- @class Gitsigns.DiffDirectory : Gitsigns.DiffNode
--- @field name string
--- @field added integer
--- @field removed integer
--- @field binary boolean

--- Fit closed directories and the header separator to the panel width.
--- @param win integer
--- @param header_lines integer
--- @param dirs table<string, Gitsigns.DiffDirectory>
local function resize_panel(win, header_lines, dirs)
  local panel, width = api.nvim_win_get_buf(win), api.nvim_win_get_width(win)

  -- Reserve space for counts and stats before clipping each closed directory label.
  local folds = {} --- @type table<string, Gitsigns.VirtTextChunk[]>
  for _, dir in pairs(dirs) do
    local count = ('(%d)'):format(dir.last - dir.first + 1)
    local stats = diffstat(dir.added, dir.removed, dir.binary)
    local stats_width = 0
    for _, chunk in ipairs(stats) do
      stats_width = stats_width + fn.strdisplaywidth(chunk[1])
    end

    -- %S clips by display cells, including wide characters and folder icons.
    local name_width = math.max(0, width - #count - stats_width - 2)
    local name = fn.printf('%.' .. name_width .. 'S', dir.name)
    local padding = math.max(1, width - fn.strdisplaywidth(name) - #count - stats_width - 1)
    folds[tostring(dir.lnum)] = vim.list_extend({
      { name .. ' ', 'Directory' },
      { count, 'Comment' },
      { string.rep(' ', padding), 'Normal' },
    }, stats)
  end

  vim.b[panel].gitsigns_diff_foldtext = folds

  -- A virtual separator follows the header without adding a selectable row.
  api.nvim_buf_set_extmark(panel, ns_header, header_lines - 1, 0, {
    id = 1,
    virt_lines = { { { string.rep('─', width), 'WinSeparator' } } },
  })
end

--- Compare each tree level separately: directories first, then names.
--- @param a Gitsigns.DiffEntry
--- @param b Gitsigns.DiffEntry
--- @return boolean
local function compare_entries(a, b)
  local ap = vim.split(a.path, '/', { plain = true })
  local bp = vim.split(b.path, '/', { plain = true })

  for i = 1, math.min(#ap, #bp) do
    if (i < #ap) ~= (i < #bp) then
      return i < #ap
    end
    if ap[i] ~= bp[i] then
      return ap[i] < bp[i]
    end
  end

  return a.path < b.path
end

--- @alias Gitsigns.DiffAction 'diff'|'target'|'base'|'stage'|'unstage'|'toggle'

--- Show panel and diff-buffer mappings in a focused popup.
--- @param panel integer
local function show_help(panel)
  local popup = require('gitsigns.popup')
  popup.close('diff_help')

  local lines = { { { 'File panel', 'Title' } } } --- @type Gitsigns.LineSpec[]
  for _, map in ipairs(api.nvim_buf_get_keymap(panel, 'n')) do
    local key = map.lhs == ' ' and '<Space>' or map.lhs
    lines[#lines + 1] = { { ('%-8s %s'):format(key, map.desc or map.rhs), 'Normal' } }
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

--- Repository review panel.
--- @class Gitsigns.DiffPanel
--- @field buf integer
--- @field tab integer
--- @field panel_win integer
--- @field right_win integer
--- @field left_win? integer
--- @field repo Gitsigns.Repo
--- @field revision? string
--- @field paths? string[]
--- @field cwd string
--- @field show_commit? boolean
--- @field base? string
--- @field target? string
--- @field entries Gitsigns.DiffEntry[]
--- @field commit? string[]
--- @field file_lnums integer[]
--- @field rows table<integer, Gitsigns.DiffNode> Nodes indexed by panel line.
--- @field nodes table<string, Gitsigns.DiffNode> Nodes indexed by repository path.
--- @field header_lines integer
--- @field dirs table<string, Gitsigns.DiffDirectory>
--- @field current_file integer
--- @field scratch table<string, integer>
--- @field retained table<integer, boolean>
--- @field busy boolean
local DiffPanel = {}
DiffPanel.__index = DiffPanel

--- Get one side of a file diff, reusing working buffers to preserve unsaved edits.
--- Missing files, gitlinks, and working-tree symlinks use scratch buffers.
--- @private
--- @async
--- @param entry Gitsigns.DiffEntry
--- @param side 'base'|'target'
--- @return integer? bufnr
--- @return boolean? created Whether this call created a disposable buffer.
--- @return boolean? loaded Whether the buffer was already loaded.
function DiffPanel:file_buffer(entry, side)
  local repo = self.repo
  local revision = self[side]
  local old = side == 'base'
  local mode = old and entry.old_mode or entry.mode
  local path = old and (entry.oldpath or entry.path) or entry.path
  local worktree = not old and not revision
  local symlink = worktree and mode == MODES.symlink

  -- Ordinary files use named buffers so edits and native cursor state survive revisits.
  if mode ~= MODES.missing and mode ~= MODES.gitlink and not symlink then
    if worktree then
      local buf = fn.bufadd(repo.toplevel .. '/' .. path)
      local loaded = api.nvim_buf_is_loaded(buf)

      fn.bufload(buf)
      vim.bo[buf].buflisted = true
      return buf, false, loaded
    end

    local _, bufnr, created, loaded = diffthis.create_revision_buf(repo, assert(revision), path)
    return bufnr, created, loaded
  end

  -- Special file types need synthetic contents, retained for the same review lifetime.
  local key = table.concat({ revision or '', mode, path }, '\0')
  local bufnr = self.scratch[key] --- @type integer?
  if bufnr and api.nvim_buf_is_loaded(bufnr) and not worktree then
    return bufnr, false, true
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

  local created = not bufnr or not api.nvim_buf_is_valid(bufnr)
  local loaded = not created and api.nvim_buf_is_loaded(assert(bufnr))
  if created then
    bufnr = api.nvim_create_buf(false, true)
    self.scratch[key] = bufnr
    vim.bo[bufnr].bufhidden = 'wipe'
  end

  -- Working-tree symlinks and gitlinks can change while their buffers stay loaded.
  -- Leave unchanged text alone so revisits preserve the buffer's cursor state.
  assert(bufnr)
  if not loaded or not vim.deep_equal(api.nvim_buf_get_lines(bufnr, 0, -1, false), text) then
    vim.bo[bufnr].modifiable = true
    api.nvim_buf_set_lines(bufnr, 0, -1, false, text)
    vim.bo[bufnr].modifiable = false
    vim.bo[bufnr].modified = false
  end

  return bufnr, created, loaded
end

--- Build panel lines and fold levels, updating the file and directory lookup tables.
--- @private
--- @return string[] lines
--- @return string[] folds
function DiffPanel:build_tree()
  -- Keep the commit metadata outside the file folds.
  local lines = {} --- @type string[]
  if self.commit then
    local sha, summary = assert(self.commit[1]):match('^(%S+) (.*)$')
    lines[1] = assert(sha)
    lines[2] = fn.strtrans(assert(summary))
  else
    lines[1] = 'Diff: ' .. fn.strtrans(self.revision or 'working tree')
  end
  self.header_lines = #lines

  local folds = {} --- @type string[]
  for i = 1, self.header_lines do
    folds[i] = '0'
  end

  -- Every lookup must refer to the same nodes and sorted entry ranges after a render.
  self.dirs = {}
  self.file_lnums = {}
  self.rows = {}
  self.nodes = {}
  table.sort(self.entries, compare_entries)

  for i, entry in ipairs(self.entries) do
    local parts = vim.split(entry.path, '/', { plain = true })
    local dir = ''

    -- Emit each ancestor once, then accumulate this file into its directory totals.
    for depth = 1, #parts - 1 do
      local name = assert(parts[depth])
      dir = dir .. name .. '/'

      if not self.dirs[dir] then
        -- Keep leading spaces in directory names visible.
        name = fn.strtrans(name):gsub('^ ', '\\ ')
        lines[#lines + 1] = string.rep('  ', depth - 1) .. ' ' .. name .. '/'

        local node = {
          path = dir,
          lnum = #lines,
          first = i,
          last = i,
          directory = true,
          name = lines[#lines],
          added = 0,
          removed = 0,
          binary = false,
        }
        self.dirs[dir] = node
        self.rows[#lines] = node
        self.nodes[dir] = node
        folds[#lines] = '>' .. depth
      end

      local stats = self.dirs[dir]

      -- Directory-first sorting keeps each directory's listed files contiguous.
      stats.last = i
      stats.added = stats.added + (entry.added or 0)
      stats.removed = stats.removed + (entry.removed or 0)
      stats.binary = stats.binary or not entry.added
    end

    -- Display rename origins in the label, but index the node by its destination.
    local path = fn.strtrans(parts[#parts])
    if entry.oldpath then
      path = fn.strtrans(entry.oldpath) .. ' -> ' .. path
    end

    lines[#lines + 1] = string.rep('  ', #parts - 1) .. ' ' .. entry.status .. ' ' .. path
    self.file_lnums[#self.file_lnums + 1] = #lines

    local node = { path = entry.path, lnum = #lines, first = i, last = i }
    self.rows[#lines] = node
    self.nodes[entry.path] = node
    folds[#lines] = tostring(#parts - 1)
  end

  -- The empty-state message and key legend also stay outside the tree folds.
  if #self.entries == 0 then
    lines[#lines + 1] = 'No changes'
  end
  vim.list_extend(lines, { '', 'g? help  <CR> open/fold  q close' })

  for i = #folds + 1, #lines do
    folds[i] = '0'
  end

  return lines, folds
end

--- Add header, status, icon, and diffstat decorations to the rendered lines.
--- @private
--- @param lines string[]
function DiffPanel:highlight_tree(lines)
  local panel = self.buf
  api.nvim_buf_set_extmark(panel, ns, #lines - 1, 0, {
    end_row = #lines,
    end_col = 0,
    hl_group = 'Comment',
  })

  if self.commit then
    api.nvim_buf_set_extmark(panel, ns, 0, 0, {
      end_row = 1,
      end_col = 0,
      hl_group = 'Identifier',
    })
    api.nvim_buf_set_extmark(panel, ns, 1, 0, {
      end_row = 2,
      end_col = 0,
      hl_group = 'Title',
    })
  end

  -- Decorate status columns independently; attach each file's diffstat only once.
  local has_devicons, devicons = pcall(require, 'nvim-web-devicons')
  for i, lnum in ipairs(self.file_lnums) do
    local entry = assert(self.entries[i])
    local col = select(2, entry.path:gsub('/', '')) * 2 + 1

    for j = 1, #entry.status do
      local hl = HIGHLIGHTS[entry.status:sub(j, j)] or 'GitSignsChange'
      if j == 1 and #entry.status == 2 then
        hl = hl:gsub('GitSigns', 'GitSignsStaged')
      end
      api.nvim_buf_set_extmark(panel, ns, lnum - 1, col + j - 1, {
        end_col = col + j,
        hl_group = hl,
        virt_text = j == 1 and diffstat(entry.added, entry.removed) or nil,
        virt_text_pos = 'right_align',
        hl_mode = 'combine',
      })
    end

    if entry.status:match('^%S $') then -- Fully staged: a clean working-tree column.
      api.nvim_buf_set_extmark(panel, ns, lnum - 1, col + 3, {
        end_col = #assert(lines[lnum]),
        hl_group = 'GitSignsDiffStaged',
      })
    end

    if has_devicons then
      local icon, hl = devicons.get_icon(fn.fnamemodify(entry.path, ':t'), nil, { default = true })
      if icon then
        -- Place icons after the status without changing the tree's text or indentation.
        api.nvim_buf_set_extmark(panel, ns, lnum - 1, col + #entry.status + 1, {
          virt_text = { { icon .. ' ', hl } },
          virt_text_pos = 'inline',
          hl_mode = 'combine',
        })
      end
    end
  end

  -- Fold labels use the same directory icon as the expanded tree.
  for _, dir in pairs(self.dirs) do
    local col = assert(dir.name:find('%S')) - 1
    local lnum = dir.lnum
    api.nvim_buf_set_extmark(panel, ns, lnum - 1, col, {
      end_row = lnum,
      end_col = 0,
      hl_group = 'Directory',
      -- Devicons supplies file icons; use a Nerd Font folder for directories.
      virt_text = has_devicons and { { ' ', 'Directory' } } or nil,
      virt_text_pos = 'inline',
      hl_mode = 'combine',
    })

    if has_devicons then
      dir.name = dir.name:sub(1, col) .. ' ' .. dir.name:sub(col + 1)
    end
  end
end

--- Render the panel and configure its window.
--- @package
function DiffPanel:render()
  local panel, panel_win = self.buf, self.panel_win
  local initial = vim.bo[panel].filetype ~= 'gitsigns-diff'

  -- Replace the text, lookup tables, and decorations as one render.
  local lines, folds = self:build_tree()
  vim.b[panel].gitsigns_diff_folds = folds

  vim.bo[panel].modifiable = true
  api.nvim_buf_clear_namespace(panel, ns, 0, -1)
  api.nvim_buf_clear_namespace(panel, ns_selection, 0, -1)
  api.nvim_buf_set_lines(panel, 0, -1, false, lines)
  self:highlight_tree(lines)

  vim.bo[panel].bufhidden = 'wipe'
  vim.bo[panel].modifiable = false
  if initial then
    vim.bo[panel].filetype = 'gitsigns-diff'
  end

  -- Hide editor furniture and use tree depth for folding, independent of status text.
  local wo = vim.wo[panel_win][0]
  wo.number = false
  wo.relativenumber = false
  wo.signcolumn = 'no'
  wo.foldcolumn = '0'

  wo.foldexpr = 'get(b:gitsigns_diff_folds, v:lnum - 1, 0)'
  wo.foldtext = 'b:gitsigns_diff_foldtext[v:foldstart]'
  wo.foldmethod = 'expr'
  wo.foldminlines = 0

  wo.wrap = true
  wo.linebreak = true
  wo.breakindent = true
  wo.spell = false
  wo.list = false

  wo.cursorline = true
  wo.winfixbuf = true
  wo.winfixwidth = true

  if initial then
    --- @diagnostic disable-next-line: deprecated
    api.nvim_win_set_width(panel_win, 36)
  end

  -- Begin with all files visible; refresh restores any selected closed directory.
  resize_panel(panel_win, self.header_lines, self.dirs)
  wo.foldenable = true
  vim.cmd('normal! zR')
  api.nvim_win_set_cursor(
    panel_win,
    { self.file_lnums[1] or (self.commit and 1 or self.header_lines + 1), 0 }
  )
end

--- Show a commit message or file diff beside the panel, recreating closed splits.
--- Disable the previous diff before switching buffers and update window IDs in place.
--- @private
--- @param buf integer
--- @param base_buf integer? Omit to show only the commit message.
--- @param jump? boolean Jump to the first hunk for a newly loaded buffer.
function DiffPanel:show_buffers(buf, base_buf, jump)
  -- Stop cursor/scroll binding before either window switches buffers, so the
  -- previous file cannot move the next file's restored cursor.
  for _, win in ipairs({ self.right_win, self.left_win }) do
    if api.nvim_win_is_valid(win) then
      api.nvim_win_call(win, function()
        vim.cmd.diffoff()
      end)
    end
  end

  -- A commit message uses only the right pane. Recreate missing panes for file diffs.
  if not base_buf then
    if self.left_win and api.nvim_win_is_valid(self.left_win) then
      api.nvim_win_close(self.left_win, false)
    end
    self.left_win = nil
  end

  if not api.nvim_win_is_valid(self.right_win) then
    api.nvim_set_current_win(self.panel_win)
    vim.cmd.vsplit({ mods = { split = 'botright', keepalt = true } })
    self.right_win = api.nvim_get_current_win()
  end

  api.nvim_set_current_win(self.right_win)
  if base_buf then
    if not self.left_win or not api.nvim_win_is_valid(self.left_win) then
      vim.cmd.vsplit({ mods = { split = 'aboveleft', keepalt = true } })
      self.left_win = api.nvim_get_current_win()
    end
  end

  api.nvim_win_set_buf(self.right_win, buf)
  api.nvim_set_current_win(self.right_win)
  if not base_buf then
    return
  end

  -- Re-enable diff binding only after both windows show the new buffers.
  assert(self.left_win)
  api.nvim_win_set_buf(self.left_win, base_buf)
  for _, win in ipairs({ self.left_win, self.right_win }) do
    api.nvim_win_call(win, function()
      vim.cmd.diffthis()
    end)
  end

  api.nvim_set_current_win(self.right_win)
  vim.cmd.diffupdate()

  if jump then
    vim.cmd('normal! gg')
    -- Do not skip a change or deletion at the first line.
    if fn.diff_hlID(1, 1) == 0 and fn.diff_filler(1) == 0 then
      vim.cmd('silent! normal! ]c')
    end
  end
end

--- Keep this buffer loaded until the last panel using it closes.
--- @private
--- @param buf integer
--- @param created boolean?
--- @param loaded boolean?
function DiffPanel:retain(buf, created, loaded)
  if not self.retained[buf] then
    local ref = buffer_refs[buf]
    if not ref then
      -- Remember the original state once, even if several panels share this buffer.
      ref = {
        refs = 0,
        bufhidden = vim.bo[buf].bufhidden,
        loaded = loaded or false,
        created = created or false,
      }
      buffer_refs[buf] = ref
    end

    ref.refs = ref.refs + 1
    self.retained[buf] = true
  end

  vim.bo[buf].bufhidden = 'hide'
end

--- @package
function DiffPanel:release()
  for buf in pairs(self.retained) do
    local ref = buffer_refs[buf]
    ref.refs = ref.refs - 1

    -- The last panel restores buffer policy without overriding a later user change.
    if ref.refs == 0 then
      buffer_refs[buf] = nil
      if api.nvim_buf_is_valid(buf) then
        if vim.bo[buf].bufhidden == 'hide' then
          vim.bo[buf].bufhidden = ref.bufhidden
        end

        -- Preserve pre-existing buffers, unsaved edits, and windows in every tab.
        if not ref.loaded and not vim.bo[buf].modified and #fn.win_findbuf(buf) == 0 then
          api.nvim_buf_delete(buf, { unload = not ref.created })
        end
      end
    end
  end
end

--- Mark the displayed file without moving the panel cursor.
--- @private
--- @param index integer
function DiffPanel:mark_current_file(index)
  self.current_file = index
  local entry = assert(self.entries[index])
  local lnum = assert(self.file_lnums[index])
  local line = assert(api.nvim_buf_get_lines(self.buf, lnum - 1, lnum, false)[1])

  -- Skip the indentation, status columns, and their separator.
  local col = select(2, entry.path:gsub('/', '')) * 2 + #entry.status + 2
  api.nvim_buf_set_extmark(self.buf, ns_selection, lnum - 1, col, {
    id = 1, -- Move the panel's single selection mark after a successful open.
    end_col = #line,
    hl_group = 'QuickFixLine',
    priority = 50, -- Preserve file icon colors above the filename highlight.
  })
end

--- Reload the tree, restoring the displayed file and selected node.
--- @private
--- @async
--- @param node Gitsigns.DiffNode
--- @param folded? boolean
function DiffPanel:refresh(node, folded)
  local new_base, new_target, new_entries, new_commit =
    git_diff(self.repo, self.revision, self.paths, self.cwd, self.show_commit)
  if not api.nvim_win_is_valid(self.panel_win) or api.nvim_get_current_tabpage() ~= self.tab then
    return
  end

  local current_entry = self.entries[self.current_file]

  -- Replace the row data together with its rendering.
  self.base, self.target, self.entries, self.commit = new_base, new_target, new_entries, new_commit
  api.nvim_set_current_win(self.panel_win)
  self:render()

  -- The displayed diff and the panel cursor can refer to different files.
  self.current_file = 0
  local current = current_entry and self.nodes[current_entry.path]
  if current then
    self:mark_current_file(current.first)
  end

  -- Keep the selected path when it survives; otherwise select a nearby file.
  if #self.entries > 0 then
    local selected = self.nodes[node.path]
    local index = math.max(1, math.min(node.directory and 1 or node.first, #self.entries))
    api.nvim_win_set_cursor(
      self.panel_win,
      { selected and selected.lnum or assert(self.file_lnums[index]), 0 }
    )

    if selected and selected.directory and folded then
      vim.cmd('normal! zc')
    end
  end
end

--- Stage or unstage the selected file or directory, then refresh the panel.
--- @private
--- @async
--- @param how 'stage'|'unstage'|'toggle'
function DiffPanel:stage_files(how)
  local lnum = api.nvim_win_get_cursor(self.panel_win)[1]
  local node = self.rows[lnum]
  if not node or self.target then
    return
  end

  local folded = node.directory and fn.foldclosed(lnum) == lnum

  -- Pass only listed descendants so directory actions respect panel filters.
  local entries = vim.list_slice(self.entries, node.first, node.last)
  local files = require('gitsigns.git').stage_files(self.repo, entries, how)
  if not files then
    return
  end

  -- Refresh attached buffers even when the Git watcher is disabled. Read the new
  -- object ID before invalidating the cached index text used to calculate hunks.
  for bufnr, bcache in pairs(cache) do
    local git_obj = bcache.git_obj
    if git_obj.repo == self.repo and vim.tbl_contains(files, bcache.file) then
      git_obj:refresh()
      if bcache:schedule() then
        bcache:invalidate(true)
        require('gitsigns.manager').update(bufnr)
      end
    end
  end

  self:refresh(node, folded)
end

--- Open the selected commit message, file diff, or one side in a new tab.
--- Discard newly created buffers if the panel closes or the user changes tabs during a read.
--- @private
--- @async
--- @param how Gitsigns.DiffAction
function DiffPanel:open_file(how)
  local lnum = api.nvim_win_get_cursor(self.panel_win)[1]
  if lnum <= 2 and self.commit and how == 'diff' then
    local buf, created, loaded = require('gitsigns.actions.show_commit').create_buf(
      self.repo,
      assert(self.target),
      self.commit
    )

    self:retain(buf, created, loaded)
    self:show_buffers(buf)
    api.nvim_buf_clear_namespace(self.buf, ns_selection, 0, -1)
    return
  end

  local node = self.rows[lnum]
  if not node or node.directory then
    return
  end

  local index = node.first
  local entry = assert(self.entries[index])

  -- Read both sides before changing windows; either read may yield to the user.
  local buf, created, loaded = self:file_buffer(entry, how == 'base' and 'base' or 'target')
  local old_buf, old_created, old_loaded
  if buf and how == 'diff' then
    old_buf, old_created, old_loaded = self:file_buffer(entry, 'base')
  end

  -- Abandoned reads must not retain buffers or change a different tab.
  if
    not buf
    or (how == 'diff' and not old_buf)
    or not api.nvim_win_is_valid(self.panel_win)
    or api.nvim_get_current_tabpage() ~= self.tab
  then
    discard(buf, created)
    discard(old_buf, old_created)
    return
  end

  self:retain(buf, created, loaded)
  if old_buf then
    self:retain(old_buf, old_created, old_loaded)
  end

  if how == 'diff' then
    self:show_buffers(buf, old_buf, not loaded)
    self:mark_current_file(index)
  else
    vim.cmd.tabnew()
    api.nvim_win_set_buf(0, buf)
  end
end

--- Serialize panel actions, retaining the repository until each action finishes.
--- @package
--- @async
--- @param how Gitsigns.DiffAction
--- @param keep_focus? boolean
function DiffPanel:run_action(how, keep_focus)
  if self.busy then
    return
  end

  self.busy = true
  local focus_win = api.nvim_get_current_win()

  -- Keep the repository alive if the panel is closed while Git is reading a file.
  self.repo:ref()
  local action = (how == 'stage' or how == 'unstage' or how == 'toggle') and self.stage_files
    or self.open_file
  local opened, open_err = pcall(action, self, how)

  -- Release action state even when a read or index update failed.
  self.repo:unref()
  self.busy = false

  if
    keep_focus
    and api.nvim_win_is_valid(focus_win)
    and api.nvim_get_current_tabpage() == self.tab
  then
    api.nvim_set_current_win(focus_win)
  end

  if not opened then
    message.error(open_err)
  end
end

--- Move through this panel's files while keeping focus in the current diff window.
--- @private
--- @param count integer Signed file offset, clamped to the first and last entries.
function DiffPanel:navigate(count)
  if self.busy or #self.file_lnums == 0 then
    return
  end

  local next_file = math.max(1, math.min(#self.file_lnums, self.current_file + count))
  if next_file == self.current_file then
    return
  end

  api.nvim_win_call(self.panel_win, function()
    api.nvim_win_set_cursor(self.panel_win, { assert(self.file_lnums[next_file]), 0 })
    vim.cmd('normal! zv')
  end)

  async.run(self.run_action, self, 'diff', true):raise_on_error()
end

--- Bind file navigation while a diff window is current, restoring mappings on leave.
--- Shared buffers then use their normal mappings in every other window or panel.
--- @package
--- @return fun() cleanup
function DiffPanel:setup_navigation()
  local group = api.nvim_create_augroup('gitsigns_diff_' .. self.buf, {})
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

  -- Install mappings only while one of this panel's diff windows is current.
  api.nvim_create_autocmd({ 'BufEnter', 'WinEnter' }, {
    group = group,
    callback = function()
      local win = api.nvim_get_current_win()
      if
        #restore > 0
        or not self.left_win
        or not api.nvim_win_is_valid(self.left_win)
        or (win ~= self.left_win and win ~= self.right_win)
      then
        return
      end

      local buf = api.nvim_get_current_buf()
      mapped_win = win
      for key, direction in pairs(directions) do
        local previous = fn.maparg(key, 'n', false, true)
        local callback = function()
          self:navigate(direction * vim.v.count1)
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

--- Bind panel actions for files, directory folds, commit metadata, and help.
--- @package
function DiffPanel:setup_keymaps()
  local panel_buf, panel_win = self.buf, self.panel_win

  --- Bind a normal-mode action to the panel buffer with its description.
  --- @param key string
  --- @param desc string
  --- @param callback fun()
  local function map(key, desc, callback)
    vim.keymap.set('n', key, callback, { buffer = panel_buf, desc = desc })
  end

  local function open_selected()
    local lnum = api.nvim_win_get_cursor(panel_win)[1]
    local node = self.rows[lnum]
    if node and node.directory then
      vim.cmd('normal! za')
    else
      async.run(self.run_action, self, 'diff'):raise_on_error()
    end
  end

  map('<CR>', 'Open file, show commit message, or toggle directory fold', open_selected)

  -- The press first enters the panel, even when another buffer had focus.
  map('<LeftRelease>', 'Open clicked entry or toggle directory fold', function()
    local mouse = fn.getmousepos()
    if mouse.winid == panel_win and mouse.line > 0 then
      open_selected()
    end
  end)

  map('<S-CR>', 'Diff file and keep focus in the panel', function()
    async.run(self.run_action, self, 'diff', true):raise_on_error()
  end)

  map('o', 'View target file (tab)', function()
    async.run(self.run_action, self, 'target'):raise_on_error()
  end)

  map('O', 'View file at base revision (tab)', function()
    async.run(self.run_action, self, 'base'):raise_on_error()
  end)

  -- Only working-tree comparisons can stage or unstage files.
  if not self.target then
    map('s', 'Stage file or directory', function()
      async.run(self.run_action, self, 'stage', true):raise_on_error()
    end)

    map('u', 'Unstage file or directory', function()
      async.run(self.run_action, self, 'unstage', true):raise_on_error()
    end)

    map('<Space>', 'Toggle file or directory staging', function()
      async.run(self.run_action, self, 'toggle', true):raise_on_error()
    end)
  end

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
--- @param show_commit? boolean Compare a commit with its first parent.
return function(revision, paths, show_commit)
  local source_win = api.nvim_get_current_win()
  local cwd = fn.getcwd()
  local repo, err = get_repo()
  if not repo then
    message.error(err or 'Not in a Git repository')
    return
  end

  -- Read the comparison before creating any review windows.
  local ok, base, target, entries, commit = pcall(git_diff, repo, revision, paths, cwd, show_commit)
  if not ok then
    repo:unref()
    message.error(base or 'Unable to read revision')
    return
  end

  if api.nvim_get_current_win() ~= source_win then
    repo:unref()
    return
  end

  -- Reuse only a pristine startup window; existing work keeps its own tab.
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

  -- Reserve the initial window for file contents and add the tree on its left.
  local tab = api.nvim_get_current_tabpage()
  local right_win = api.nvim_get_current_win()
  vim.bo.bufhidden = 'wipe'

  vim.cmd.vsplit({ mods = { split = 'topleft', keepalt = true } })
  local panel_win = api.nvim_get_current_win()
  local panel = api.nvim_create_buf(false, true)
  api.nvim_win_set_buf(panel_win, panel)
  api.nvim_buf_set_name(panel, ('gitsigns-diff://%s//%d'):format(repo.gitdir, tab))

  local self = setmetatable({
    buf = panel,
    tab = tab,
    panel_win = panel_win,
    right_win = right_win,

    repo = repo,
    revision = revision,
    paths = paths,
    cwd = cwd,
    show_commit = show_commit,

    base = base,
    target = target,
    entries = entries,
    commit = commit,

    -- Tree lookups are rebuilt together during rendering.
    file_lnums = {},
    rows = {},
    nodes = {},
    header_lines = 0,
    dirs = {},
    current_file = 1,

    -- Kept across file switches until this review closes.
    scratch = {},
    retained = {},
    busy = false,
  }, DiffPanel)

  self:render()

  -- Tie window updates, temporary mappings, and retained buffers to the panel.
  local resize = api.nvim_create_autocmd('WinResized', {
    callback = function()
      if api.nvim_win_is_valid(panel_win) then
        resize_panel(panel_win, self.header_lines, self.dirs)
      end
    end,
  })

  local unmap = self:setup_navigation()
  api.nvim_create_autocmd('BufWipeout', {
    buffer = panel,
    once = true,
    callback = function()
      unmap()
      api.nvim_del_autocmd(resize)
      repo:unref()

      -- Wait for tab closure to remove its windows before checking other users.
      vim.schedule(function()
        self:release()
      end)
    end,
  })

  self:setup_keymaps()

  if #entries > 0 then
    self:run_action('diff', true)
  end
end
