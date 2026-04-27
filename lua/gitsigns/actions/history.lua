--- File history browser.
---
--- The history command renders a commit list for one tracked path, opens
--- revisions or commits from that list, and keeps the history panel attached to
--- the active revision/source buffer without stealing ownership from it.
local async = require('gitsigns.async')
local cache = require('gitsigns.cache').cache
local config = require('gitsigns.config').config
local log = require('gitsigns.debug.log')
local message = require('gitsigns.message')
local inspection = require('gitsigns.actions.inspection')

local api = vim.api

local ns = api.nvim_create_namespace('gitsigns_history_win')
local ns_state = api.nvim_create_namespace('gitsigns_history_state')

local M = {}

--- @class (exact) Gitsigns.HistoryEntry
--- @field sha string
--- @field abbrev_sha string
--- @field author_date string
--- @field author string
--- @field refs string
--- @field added? string
--- @field removed? string
--- @field rename_from? string
--- @field summary string
--- @field filename string
--- @field synthetic? true
--- @field last_changed_abbrev_sha? string
--- @field last_changed_summary? string

--- Highlight a line in the history window.
--- @param bufnr integer
--- @param lnum integer
--- @param hl_group string
local function hl_line(bufnr, lnum, hl_group)
  api.nvim_buf_set_extmark(bufnr, ns_state, lnum - 1, 0, {
    end_row = lnum,
    hl_eol = true,
    end_col = 0,
    hl_group = hl_group,
  })
end

--- @param path string
--- @return string? old_path
--- @return string? new_path
local function parse_rename_path(path)
  local prefix, old_path, new_path, suffix = path:match('^(.-){(.*) => (.*)}(.*)$')
  if old_path then
    return prefix .. old_path .. suffix, prefix .. new_path .. suffix
  end

  return path:match('^(.*) => (.*)$')
end

--- @param lines string[] `git log --format=... --numstat` output, with blank separators.
--- @param fallback_relpath string Path used when a commit has no numstat path line.
--- @return Gitsigns.HistoryEntry[]
local function parse_git_log_entries(lines, fallback_relpath)
  local entries = {} --- @type Gitsigns.HistoryEntry[]
  local pending --- @type Gitsigns.HistoryEntry?

  for _, line in ipairs(lines) do
    local sha, abbrev_sha, author_date, author, refs, summary =
      line:match('^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$')

    if sha and abbrev_sha and author_date and author and refs and summary then
      if pending then
        entries[#entries + 1] = pending
      end

      pending = {
        sha = sha,
        abbrev_sha = abbrev_sha,
        author_date = author_date,
        author = author,
        refs = refs,
        summary = summary,
        filename = fallback_relpath,
      }
    elseif pending then
      local added, removed, path = line:match('^([%d-]+)\t([%d-]+)\t(.+)$')
      if added and removed and path then
        pending.added = added
        pending.removed = removed

        local rename_from, filename = parse_rename_path(path)
        if rename_from and filename then
          pending.rename_from = rename_from
          pending.filename = filename
        else
          -- Keep the per-entry path so opening older revisions still works across renames.
          pending.filename = path
        end
      end
    end
  end

  if pending then
    entries[#entries + 1] = pending
  end

  return entries
end

--- @param ...string
local function git_log_args(...)
  return vim.list_extend({
    'log',
    '--abbrev=8',
    '--date=short',
    '--format=format:%H\t%h\t%ad\t%an\t%D\t%s',
  }, { ... })
end

--- @param hist_relpath string
--- @param source_sha? string
local function file_history_log_args(hist_relpath, source_sha)
  local args = git_log_args('--follow', '--numstat')
  if source_sha then
    vim.list_extend(args, { '-1', source_sha })
  end
  vim.list_extend(args, { '--', hist_relpath })
  return args
end

--- Insert a source row when the shown revision did not touch the file.
--- This keeps the source marker on the actual buffer revision instead of
--- snapping it to the nearest real file-change commit.
--- @async
--- @param repo Gitsigns.Repo
--- @param entries Gitsigns.HistoryEntry[]
--- @param source_sha string
--- @param source_relpath string
--- @param hist_relpath string
local function maybe_insert_source_entry(repo, entries, source_sha, source_relpath, hist_relpath)
  for _, entry in ipairs(entries) do
    if entry.sha == source_sha then
      return
    end
  end

  -- The source commit may not touch this path, so fetch its row metadata
  -- separately from the path-limited log used to position it in file history.
  local source_log = repo:command(git_log_args('-1', source_sha), { ignore_error = true })
  local source_entry = parse_git_log_entries(source_log, source_relpath)[1]
  if not source_entry then
    return
  end

  local last_changed_log =
    repo:command(file_history_log_args(hist_relpath, source_sha), { ignore_error = true })
  local last_changed = parse_git_log_entries(last_changed_log, hist_relpath)[1]

  local insert_at = #entries + 1
  if last_changed then
    for i, entry in ipairs(entries) do
      if entry.sha == last_changed.sha then
        insert_at = i
        break
      end
    end
  end

  source_entry.synthetic = true
  source_entry.last_changed_abbrev_sha = last_changed and last_changed.abbrev_sha
  source_entry.last_changed_summary = last_changed and last_changed.summary
  table.insert(entries, insert_at, source_entry)
end

--- @param bufnr integer
--- @param entries Gitsigns.HistoryEntry[]
--- @return integer
local function render(bufnr, entries)
  local lines = {} --- @type string[]
  local width = 0

  for i, entry in ipairs(entries) do
    local line = entry.abbrev_sha .. '  ' .. (entry.synthetic and '* ' or '') .. entry.summary

    lines[i] = line
    width = math.max(width, vim.fn.strdisplaywidth(line))
  end

  local modifiable = vim.bo[bufnr].modifiable
  vim.bo[bufnr].modifiable = true
  api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = modifiable
  api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

  for i, entry in ipairs(entries) do
    local row = i - 1
    local sha_end = #entry.abbrev_sha

    api.nvim_buf_set_extmark(bufnr, ns, row, 0, {
      end_col = sha_end,
      hl_group = 'Directory',
    })

    if entry.synthetic then
      api.nvim_buf_set_extmark(bufnr, ns, row, sha_end + 2, {
        end_col = sha_end + 3,
        hl_group = 'Special',
      })
    end
  end

  return width
end

--- @alias Gitsigns.HistoryOpen 'edit'|'vsplit'|'tabnew'

--- @param source_win integer
--- @param hist_win integer
--- @return integer?
local function get_target_win(source_win, hist_win)
  local tabpage = api.nvim_win_is_valid(hist_win) and api.nvim_win_get_tabpage(hist_win) or 0
  local target_win = inspection.find_target_win(tabpage, source_win)
  if target_win then
    return target_win
  end

  if api.nvim_win_is_valid(hist_win) then
    return hist_win
  end
end

--- @param source_win integer
--- @param fallback_bufnr integer
--- @return integer
local function get_action_bufnr(source_win, fallback_bufnr)
  if api.nvim_win_is_valid(source_win) then
    local source_bufnr = api.nvim_win_get_buf(source_win)
    if cache[source_bufnr] then
      return source_bufnr
    end
  end

  -- Revision buffers opened from history are wiped when replaced, so follow
  -- the live source window when possible instead of pinning the original bufnr.
  return fallback_bufnr
end

--- @async
--- @param source_win integer
--- @param hist_win integer
--- @param open Gitsigns.HistoryOpen
--- @param bufnr integer
--- @param entry Gitsigns.HistoryEntry
local function show_commit(source_win, hist_win, open, bufnr, entry)
  local target_win = get_target_win(source_win, hist_win)
  if not target_win then
    return
  end

  local action_bufnr = get_action_bufnr(target_win, bufnr)
  api.nvim_set_current_win(target_win)
  require('gitsigns.actions.show_commit')(entry.sha, open, action_bufnr)
end

--- @async
--- @param source_win integer
--- @param hist_win integer
--- @param open Gitsigns.HistoryOpen
--- @param bufnr integer
--- @param entry Gitsigns.HistoryEntry
local function show_buffer(source_win, hist_win, open, bufnr, entry)
  local target_win = get_target_win(source_win, hist_win)
  if not target_win then
    return
  end

  local target_is_hist = target_win == hist_win
  local action_bufnr = get_action_bufnr(target_win, bufnr)
  local old_tabpage = api.nvim_win_get_tabpage(target_win)
  local move_panels = open == 'tabnew'
    or (
      open == 'edit'
      and not target_is_hist
      and not inspection.is_revision_buf(api.nvim_win_get_buf(target_win))
    )

  api.nvim_set_current_win(target_win)
  if move_panels then
    if not inspection.show_revision_in_new_tab(action_bufnr, entry.sha, entry.filename) then
      return
    end

    local hist_vert = api.nvim_win_is_valid(hist_win) and vim.wo[hist_win][0].winfixwidth or false
    M.history({
      vertical = hist_vert,
      split = hist_vert and 'aboveleft' or 'belowright',
    })
    inspection.close_panels(old_tabpage)
    return
  elseif open == 'edit' and target_is_hist then
    -- Keep the history browser usable even if the right-hand buffer was closed.
    vim.cmd.vsplit({ mods = { keepalt = true, split = 'botright' } })
  elseif open ~= 'edit' then
    vim.cmd[open]({ mods = { keepalt = true } })
  end

  local did_attach =
    require('gitsigns.actions.diffthis').show(action_bufnr, entry.sha, entry.filename)
  if not did_attach then
    return
  end

  if open == 'edit' and api.nvim_win_is_valid(hist_win) then
    api.nvim_set_current_win(hist_win)
  end
end

--- @param hist_win integer
--- @param entries Gitsigns.HistoryEntry[]
--- @return Gitsigns.HistoryEntry?
local function get_entry(hist_win, entries)
  if api.nvim_win_is_valid(hist_win) then
    local lnum = api.nvim_win_get_cursor(hist_win)[1]
    return entries[lnum]
  end
end

--- @class (exact) Gitsigns.HistoryPickerAction
--- @field desc string
--- @field run fun()

--- @class (exact) Gitsigns.HistoryStatusAction
--- @field key string
--- @field status string

--- @class (exact) Gitsigns.HistoryAction : Gitsigns.HistoryPickerAction, Gitsigns.HistoryStatusAction

--- @class (exact) Gitsigns.HistoryKeymappedActionsOpts
--- @field bufnr integer
--- @field actions Gitsigns.HistoryAction[]
--- @field prompt fun(): string
--- @field format_item fun(action: Gitsigns.HistoryPickerAction): string
--- @field run_action fun(action: Gitsigns.HistoryPickerAction)
--- @param opts Gitsigns.HistoryKeymappedActionsOpts
local function set_keymapped_actions(opts)
  local picker_actions = {} --- @type Gitsigns.HistoryPickerAction[]

  for i, action in ipairs(opts.actions) do
    local picker_action = {
      desc = action.desc,
      run = action.run,
    }
    picker_actions[i] = picker_action

    vim.keymap.set('n', action.key, function()
      opts.run_action(picker_action)
    end, {
      buffer = opts.bufnr,
      desc = action.desc,
    })
  end

  vim.keymap.set('n', '?', function()
    vim.ui.select(picker_actions, {
      prompt = opts.prompt(),
      format_item = opts.format_item,
    }, function(action)
      if action then
        opts.run_action(action)
      end
    end)
  end, {
    buffer = opts.bufnr,
    desc = 'Open action picker',
  })
end

--- @param actions Gitsigns.HistoryStatusAction[]
--- @return string
local function format_statusline(actions)
  local items = {} --- @type { keys: string[], status: string }[]
  local by_status = {} --- @type table<string,{ keys: string[], status: string }>

  for _, action in ipairs(actions) do
    local item = by_status[action.status]
    if item then
      item.keys[#item.keys + 1] = action.key
    else
      item = { keys = { action.key }, status = action.status }
      by_status[action.status] = item
      items[#items + 1] = item
    end
  end

  local chunks = {} --- @type string[]
  for i, item in ipairs(items) do
    chunks[i] = table.concat(item.keys, '/') .. ' ' .. item.status
  end

  return ' ' .. table.concat(chunks, '  ') .. ' '
end

--- @param hist_win integer
--- @param entry Gitsigns.HistoryEntry
local function set_winbar(hist_win, entry)
  if not api.nvim_win_is_valid(hist_win) then
    return
  end

  local wlo = vim.wo[hist_win][0]
  -- Winbars use statusline syntax, so '%' needs escaping.
  local file_label = vim.fn.pathshorten(entry.filename):gsub('%%', '%%%%')
  wlo.winbar = ' History %<' .. file_label .. ' '
end

--- @param detail_lines Gitsigns.VirtTextChunk[][]
--- @param label string
--- @param value string
--- @param value_hl string
local function add_detail_line(detail_lines, label, value, value_hl)
  detail_lines[#detail_lines + 1] = {
    { '  ' .. label .. ' ', 'Comment' },
    { value, value_hl },
  }
end

--- @param detail_lines Gitsigns.VirtTextChunk[][]
--- @param added? string
--- @param removed? string
local function add_stats_line(detail_lines, added, removed)
  if not added or not removed then
    return
  end

  if added == '-' or removed == '-' then
    add_detail_line(detail_lines, 'changes', 'binary', 'Comment')
    return
  end

  detail_lines[#detail_lines + 1] = {
    { '  changes ', 'Comment' },
    { '+' .. added, 'DiffAdd' },
    { ' ', 'Comment' },
    { '-' .. removed, 'DiffDelete' },
  }
end

--- @param hist_bufnr integer
--- @param lnum integer
--- @param entry Gitsigns.HistoryEntry
--- @param relpath string
--- @param show_info boolean
--- @param prs_loading boolean
--- @param prs gitsigns.gh.PrInfo[]|false|nil
local function set_detail(hist_bufnr, lnum, entry, relpath, show_info, prs_loading, prs)
  if not api.nvim_buf_is_valid(hist_bufnr) then
    return
  end

  if not show_info then
    return
  end

  local detail_lines = {
    {
      { '  ' .. entry.author_date, 'Label' },
      { '  ' .. entry.author, 'MoreMsg' },
    },
  } --- @type Gitsigns.VirtTextChunk[][]

  if entry.refs ~= '' then
    add_detail_line(detail_lines, 'refs', entry.refs, 'Title')
  end

  if entry.synthetic then
    add_detail_line(detail_lines, 'status', 'unchanged in this commit', 'Comment')
    if entry.last_changed_abbrev_sha and entry.last_changed_summary then
      add_detail_line(
        detail_lines,
        'last changed',
        entry.last_changed_abbrev_sha .. '  ' .. entry.last_changed_summary,
        'Directory'
      )
    end
  else
    add_stats_line(detail_lines, entry.added, entry.removed)

    if entry.rename_from then
      add_detail_line(detail_lines, 'renamed from', entry.rename_from, 'Directory')
    elseif entry.filename ~= relpath then
      add_detail_line(detail_lines, 'old path', entry.filename, 'Directory')
    end
  end

  if prs and next(prs) then
    local labels = {} --- @type string[]
    for i, pr in ipairs(prs) do
      labels[i] = ('#%s'):format(pr.number)
    end
    add_detail_line(detail_lines, 'prs', table.concat(labels, ' '), 'Title')
  end
  if prs_loading then
    add_detail_line(detail_lines, 'prs', 'loading...', 'Comment')
  end
  api.nvim_buf_set_extmark(hist_bufnr, ns_state, lnum - 1, 0, {
    virt_lines = detail_lines,
  })
end

--- @param source_bufnr integer
--- @param bcache Gitsigns.CacheEntry
--- @return string?
local function get_source_sha(source_bufnr, bcache)
  local source_sha = vim.b[source_bufnr].gitsigns_history_source_sha
  if type(source_sha) == 'string' and source_sha ~= '' then
    return source_sha
  end

  source_sha = bcache.git_obj.revision
  if not source_sha or vim.startswith(source_sha, ':') or source_sha == 'FILE' then
    return
  end

  return source_sha
end

--- @async
--- @param bufnr integer
--- @param bcache Gitsigns.CacheEntry
--- @param relpath string
--- @return Gitsigns.HistoryEntry[]?
--- @return string? hist_relpath
local function load_history_entries(bufnr, bcache, relpath)
  local source_sha = bcache.git_obj.revision
  if source_sha and source_sha ~= 'FILE' and not vim.startswith(source_sha, ':') then
    if not source_sha:match('^%x+$') or #source_sha < 40 then
      local resolved = bcache.git_obj.repo:command(
        { 'rev-parse', '--verify', source_sha .. '^{commit}' },
        { ignore_error = true }
      )[1]
      if type(resolved) == 'string' and resolved:match('^%x+$') and #resolved == 40 then
        vim.b[bufnr].gitsigns_history_source_sha = resolved
      end
    end
  end

  local hist_relpath = vim.b[bufnr].gitsigns_history_relpath
  if type(hist_relpath) ~= 'string' then
    hist_relpath = relpath
  end

  local history, stderr = bcache.git_obj.repo:command(file_history_log_args(hist_relpath), {
    ignore_error = true,
  })

  if stderr then
    local msg = 'Error running git-log: ' .. stderr
    message.error('%s', msg)
    log.eprint(msg)
    return
  end

  local entries = parse_git_log_entries(history, hist_relpath)
  if #entries == 0 then
    message.warn('No history for current buffer')
    return
  end

  source_sha = get_source_sha(bufnr, bcache)
  if source_sha then
    maybe_insert_source_entry(bcache.git_obj.repo, entries, source_sha, relpath, hist_relpath)
  end

  return entries, hist_relpath
end

--- @param source_win integer
--- @param bufnr integer
--- @param entries Gitsigns.HistoryEntry[]
--- @return integer?
local function get_source_lnum(source_win, bufnr, entries)
  if not api.nvim_win_is_valid(source_win) then
    return
  end

  local source_bufnr = api.nvim_win_get_buf(source_win)
  local bcache = cache[source_bufnr]
  if not bcache then
    return
  end

  local source_relpath = bcache.git_obj.relpath
  if not source_relpath then
    return
  end

  if source_bufnr == bufnr and not bcache.git_obj.revision then
    -- The live buffer does not map to a single commit entry, so keep the
    -- source marker on the newest history item for the current path.
    for i, entry in ipairs(entries) do
      if entry.filename == source_relpath then
        return i
      end
    end
    return
  end

  local source_sha = get_source_sha(source_bufnr, bcache)
  if not source_sha then
    return
  end

  for i, entry in ipairs(entries) do
    -- File history has at most one row per commit, so matching by SHA keeps
    -- revision buffers anchored even when the file had a different name then.
    if entry.sha == source_sha then
      return i
    end
  end
end

--- @param hist_bufnr integer
--- @param hist_win integer
--- @param source_win integer
--- @param bufnr integer
--- @param entries Gitsigns.HistoryEntry[]
local function update_highlights(hist_bufnr, hist_win, source_win, bufnr, entries)
  if not api.nvim_buf_is_valid(hist_bufnr) then
    return
  end

  local cursor_lnum = api.nvim_win_is_valid(hist_win) and api.nvim_win_get_cursor(hist_win)[1]
  if cursor_lnum and entries[cursor_lnum] then
    hl_line(hist_bufnr, cursor_lnum, 'CursorLine')
  end

  local source_lnum = get_source_lnum(source_win, bufnr, entries)
  if source_lnum then
    hl_line(hist_bufnr, source_lnum, 'Visual')
  end
end

--- @param hist_win integer
local function scroll_cursor_into_view(hist_win)
  if not api.nvim_win_is_valid(hist_win) then
    return
  end

  pcall(api.nvim_win_call, hist_win, function()
    local lnum = vim.fn.line('.')
    local height = vim.fn.winheight(0)
    if height < 1 then
      return
    end

    local line_count = vim.fn.line('$')
    local scrolloff = math.min(math.max(vim.wo.scrolloff, 0), math.floor((height - 1) / 2))
    local topline = vim.fn.line('w0')
    local botline = vim.fn.line('w$')

    -- Avoid cursor jumps here: refresh may run from CursorMoved, and moving the
    -- cursor while repairing the viewport can schedule another refresh.
    if lnum < topline + scrolloff then
      vim.fn.winrestview({ topline = math.max(1, lnum - scrolloff) })
    elseif lnum > botline - scrolloff then
      local max_topline = math.max(1, line_count - height + 1)
      vim.fn.winrestview({
        topline = math.min(max_topline, math.max(1, lnum + scrolloff - height + 1)),
      })
    end
  end)
end

--- @class (exact) Gitsigns.HistoryPrLoader
--- @field private _toplevel string
--- @field private _refresh fun()
--- @field private _cache table<string, gitsigns.gh.PrInfo[]|false>
--- @field private _failed table<string, boolean?>
--- @field private _loading table<string, boolean?>
--- @field private _last_detail_sha? string
--- @field private _last_show_info boolean
local PrLoader = {}
PrLoader.__index = PrLoader

--- @param toplevel string
--- @param refresh fun()
--- @return Gitsigns.HistoryPrLoader
function PrLoader.new(toplevel, refresh)
  return setmetatable({
    _toplevel = toplevel,
    _refresh = refresh,
    _cache = {},
    _failed = {},
    _loading = {},
    _last_show_info = false,
  }, PrLoader)
end

--- @param sha string
function PrLoader:load(sha)
  if self._cache[sha] ~= nil or self._failed[sha] or self._loading[sha] then
    return
  end

  self._loading[sha] = true
  async
    .run(function()
      local prs_by_sha = require('gitsigns.gh').associated_prs_many({ sha }, self._toplevel)
      async.schedule()

      self._loading[sha] = nil
      local prs = prs_by_sha and prs_by_sha[sha]
      if prs ~= nil then
        self._cache[sha] = prs
        self._failed[sha] = nil
      else
        self._failed[sha] = true
      end

      self._refresh()
    end)
    :raise_on_error()
end

--- @param sha string?
--- @param show_info boolean
--- @return gitsigns.gh.PrInfo[]|false|nil prs
--- @return boolean prs_loading
function PrLoader:get(sha, show_info)
  if not sha then
    self._last_detail_sha = nil
    self._last_show_info = show_info
    return nil, false
  end

  if show_info and (sha ~= self._last_detail_sha or not self._last_show_info) then
    -- Retry inconclusive lookups when the user re-enters a row or re-enables
    -- expanded info, but avoid hammering `gh` on every refresh while the same
    -- failed row stays selected.
    self._failed[sha] = nil
  end

  if config.gh and show_info then
    self:load(sha)
  end

  self._last_detail_sha = sha
  self._last_show_info = show_info
  return self._cache[sha], self._loading[sha] == true
end

--- @class (exact) Gitsigns.HistorySession.Opts
--- @field source_win integer
--- @field bufnr integer
--- @field hist_win integer
--- @field hist_relpath string
--- @field entries Gitsigns.HistoryEntry[]
--- @field toplevel string

--- @class (exact) Gitsigns.HistorySession
--- @field private _source_win integer
--- @field private _source_bufnr integer
--- @field private _bufnr integer
--- @field private _hist_win integer
--- @field private _hist_relpath string
--- @field private _entries Gitsigns.HistoryEntry[]
--- @field private _pr_loader Gitsigns.HistoryPrLoader
local HistorySession = {}
HistorySession.__index = HistorySession

--- @param opts Gitsigns.HistorySession.Opts
function HistorySession.start(opts)
  local self = setmetatable({
    _source_win = opts.source_win,
    _source_bufnr = api.nvim_win_get_buf(opts.source_win),
    _bufnr = opts.bufnr,
    _hist_win = opts.hist_win,
    _hist_relpath = opts.hist_relpath,
    _entries = opts.entries,
  }, HistorySession)

  self._pr_loader = PrLoader.new(opts.toplevel, function()
    if api.nvim_win_is_valid(self._hist_win) then
      self:_refresh()
    end
  end)

  api.nvim_win_set_cursor(
    self._hist_win,
    { get_source_lnum(self._source_win, self._bufnr, self._entries) or 1, 0 }
  )
  scroll_cursor_into_view(self._hist_win)

  self:_refresh()
  self:_setup_autocmds()
  self:_setup_keymaps()
end

--- @private
function HistorySession:_setup_autocmds()
  local hist_bufnr = api.nvim_win_get_buf(self._hist_win)
  local group = api.nvim_create_augroup('GitsignsHistory' .. hist_bufnr, { clear = true })

  api.nvim_create_autocmd('CursorMoved', {
    buffer = hist_bufnr,
    group = group,
    callback = function()
      self:_refresh()
    end,
  })

  api.nvim_create_autocmd({ 'BufEnter', 'WinEnter' }, {
    group = group,
    callback = function()
      self:_refresh()
    end,
  })

  api.nvim_create_autocmd('BufWipeout', {
    buffer = hist_bufnr,
    group = group,
    once = true,
    callback = function()
      pcall(api.nvim_del_augroup_by_id, group)
    end,
  })
end

--- @private
function HistorySession:_setup_keymaps()
  local hist_bufnr = api.nvim_win_get_buf(self._hist_win)

  --- @param fn async fun(source_win: integer, history_win: integer, open: Gitsigns.HistoryOpen, bufnr: integer, entry: Gitsigns.HistoryEntry)
  --- @param open Gitsigns.HistoryOpen
  --- @return fun()
  local function entry_action(fn, open)
    return function()
      local entry = assert(get_entry(self._hist_win, self._entries))
      async.run(fn, self._source_win, self._hist_win, open, self._bufnr, entry):raise_on_error()
    end
  end

  local actions = {
    {
      key = '<CR>',
      status = 'open',
      desc = 'Open buffer revision',
      run = entry_action(show_buffer, 'edit'),
    },
    {
      key = 'v',
      status = 'split',
      desc = 'Open buffer revision in a vertical split',
      run = entry_action(show_buffer, 'vsplit'),
    },
    {
      key = 't',
      status = 'tab',
      desc = 'Open buffer revision in a new tab',
      run = entry_action(show_buffer, 'tabnew'),
    },
    {
      key = 'gv',
      status = 'commit',
      desc = 'Show commit in a vertical split',
      run = entry_action(show_commit, 'vsplit'),
    },
    {
      key = 'gt',
      status = 'commit',
      desc = 'Show commit in a new tab',
      run = entry_action(show_commit, 'tabnew'),
    },
    {
      key = 'i',
      status = 'info',
      desc = 'Toggle expanded inline info',
      run = function()
        vim.b[hist_bufnr].gitsigns_history_show_info =
          not vim.b[hist_bufnr].gitsigns_history_show_info
        self:_refresh()
      end,
    },
    {
      key = 'q',
      status = 'quit',
      desc = 'Close history',
      run = function()
        self:_close()
      end,
    },
  } --- @type Gitsigns.HistoryAction[]

  local status_actions = {} --- @type Gitsigns.HistoryStatusAction[]
  vim.list_extend(status_actions, actions)
  status_actions[#status_actions + 1] = { key = '?', status = 'menu' }
  vim.wo[self._hist_win][0].statusline = format_statusline(status_actions)

  set_keymapped_actions({
    bufnr = hist_bufnr,
    actions = actions,
    prompt = function()
      local entry = assert(get_entry(self._hist_win, self._entries))
      return ('Gitsigns history: %s'):format(entry.abbrev_sha)
    end,
    format_item = function(action)
      return action.desc
    end,
    run_action = function(action)
      action.run()
    end,
  })
end

--- @private
function HistorySession:_close()
  if not api.nvim_win_is_valid(self._hist_win) then
    return
  end

  local win = api.nvim_get_current_win()
  if api.nvim_win_get_buf(win) == api.nvim_win_get_buf(self._hist_win) then
    vim.cmd.quit()
  else
    pcall(api.nvim_win_close, self._hist_win, false)
  end
end

--- @private
function HistorySession:_refresh()
  if not api.nvim_win_is_valid(self._hist_win) then
    return
  end

  local tabpage = api.nvim_win_get_tabpage(self._hist_win)
  local new_source_win = inspection.find_target_win(tabpage, self._source_win)
  if not new_source_win then
    if inspection.has_target_candidate_win(tabpage, self._source_win) then
      return
    end
    pcall(api.nvim_win_close, self._hist_win, true)
    return
  end
  self._source_win = new_source_win

  local hist_bufnr = api.nvim_win_get_buf(self._hist_win)

  local new_source_bufnr = api.nvim_win_get_buf(self._source_win)
  if new_source_bufnr ~= self._source_bufnr then
    self._source_bufnr = new_source_bufnr
    local source_lnum = get_source_lnum(self._source_win, self._bufnr, self._entries)
    if source_lnum then
      api.nvim_win_set_cursor(self._hist_win, { source_lnum, 0 })
    end
  end

  local show_info = vim.b[hist_bufnr].gitsigns_history_show_info == true --[[@as boolean]]
  local lnum = api.nvim_win_get_cursor(self._hist_win)[1]
  local entry = self._entries[lnum]
  local prs, prs_loading = self._pr_loader:get(entry and entry.sha, show_info)

  api.nvim_buf_clear_namespace(hist_bufnr, ns_state, 0, -1)
  if entry then
    set_winbar(self._hist_win, entry)
    set_detail(hist_bufnr, lnum, entry, self._hist_relpath, show_info, prs_loading, prs)
    update_highlights(hist_bufnr, self._hist_win, self._source_win, self._bufnr, self._entries)
    scroll_cursor_into_view(self._hist_win)
  end
end

--- @param opts? Gitsigns.CmdParams.Smods
--- @param bcache Gitsigns.CacheEntry
--- @param hist_relpath string
--- @param entries Gitsigns.HistoryEntry[]
--- @return integer history_win
local function create_history_window(opts, bcache, hist_relpath, entries)
  local vertical = opts and opts.vertical or false
  local split = opts and opts.split
  if not split or split == '' then
    split = vertical and 'aboveleft' or 'belowright'
  end

  local hist_win = inspection.find_panel_win(0, 'gitsigns-history')
  local blame_win = inspection.find_panel_win(0, 'gitsigns-blame')

  local hist_bufnr = api.nvim_create_buf(false, true)

  --- Create the history window
  if not hist_win then
    if blame_win then
      api.nvim_set_current_win(blame_win)
      vertical = false
      -- Blame lines track the source buffer, so history belongs under the
      -- source+blame row rather than under only the source window.
      split = 'botright'
    end
    vim.cmd[vertical and 'vsplit' or 'split']({ mods = { keepalt = true, split = split } })
    hist_win = api.nvim_get_current_win()
    vim.wo[hist_win][0].scrollbind = false
  end

  if vim.fn.exists('&winfixbuf') == 1 then
    vim.wo[hist_win][0].winfixbuf = false
  end
  api.nvim_win_set_buf(hist_win, hist_bufnr)

  api.nvim_buf_set_name(
    hist_bufnr,
    (bcache:get_rev_bufname(nil, hist_relpath):gsub('^gitsigns:', 'gitsigns-history:'))
  )
  api.nvim_set_current_win(hist_win)

  local content_width = render(hist_bufnr, entries)

  if vertical then
    local max_width = math.max(32, math.floor(vim.o.columns * 0.4))
    local width = math.max(math.min(content_width + 1, max_width), math.min(24, max_width))
    -- Keep the browser narrow enough that the file view remains the primary pane.
    api.nvim_win_set_width(hist_win, width)
  else
    local max_height = math.max(4, math.floor(math.max(vim.o.lines - 2, 1) * 0.35))
    local height = math.max(math.min(#entries, max_height), math.min(4, max_height))
    -- Keep the browser short enough that the file view remains the primary pane.
    api.nvim_win_set_height(hist_win, height)
  end

  local bo = vim.bo[hist_bufnr]
  bo.buftype = 'nofile'
  bo.bufhidden = 'wipe'
  bo.modifiable = false
  bo.filetype = 'gitsigns-history'
  vim.b[hist_bufnr].gitsigns_history_show_info = false

  local wlo = vim.wo[hist_win][0]
  wlo.foldcolumn = '0'
  wlo.foldenable = false
  wlo.number = false
  wlo.relativenumber = false
  wlo.signcolumn = 'no'
  wlo.spell = false
  wlo.scrollbind = false
  wlo.winfixwidth = vertical
  wlo.winfixheight = not vertical
  wlo.wrap = false
  wlo.list = false

  if vim.fn.exists('&winfixbuf') == 1 then
    wlo.winfixbuf = true
  end

  return hist_win
end

--- @async
--- @param opts? Gitsigns.CmdParams.Smods
function M.history(opts)
  local source_win, bufnr, bcache = inspection.get_source_context(api.nvim_get_current_win())

  if not bcache then
    log.dprint('Not attached')
    return
  end

  local relpath = bcache.git_obj.relpath
  if not relpath then
    message.warn('No tracked path for current buffer')
    return
  end

  local entries, hist_relpath = load_history_entries(bufnr, bcache, relpath)
  if not entries or not hist_relpath then
    return
  end

  local hist_win = create_history_window(opts, bcache, hist_relpath, entries)

  HistorySession.start({
    source_win = source_win,
    bufnr = bufnr,
    hist_win = hist_win,
    hist_relpath = hist_relpath,
    entries = entries,
    toplevel = bcache.git_obj.repo.toplevel,
  })
end

return M
