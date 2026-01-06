local async = require('gitsigns.async')
local cache = require('gitsigns.cache').cache
local log = require('gitsigns.debug.log')
local util = require('gitsigns.util')

local get_temp_hl = require('gitsigns.highlight').get_temp_hl

local api = vim.api

local hash_colors = {} --- @type table<integer,string>

local ns = api.nvim_create_namespace('gitsigns_blame_win')
local ns_hl = api.nvim_create_namespace('gitsigns_blame_win_hl')

--- Convert a hex char to a rgb color component
---
--- Taken from vim-fugitive:
--- Avoid color components lower than 0x20 and higher than 0xdf to help
--- avoid colors that blend into the background, light or dark.
--- @param x string hex char
--- @return integer
local function mod(x)
  local y = assert(tonumber(x, 16))
  return math.min(0xdf, 0x20 + math.floor((y * 0x10 + (15 - y)) * 0.75))
end

--- Highlight a line in the blame window
--- @param bufnr integer
--- @param nsl integer
--- @param lnum integer
--- @param hl_group string
local function hl_line(bufnr, nsl, lnum, hl_group)
  api.nvim_buf_set_extmark(bufnr, nsl, lnum - 1, 0, {
    end_row = lnum,
    hl_eol = true,
    end_col = 0,
    hl_group = hl_group,
  })
end

--- Taken from vim-fugitive
--- Use 3 characters of the commit hash, limiting the maximum total colors to
--- 4,096.
--- @param sha string
--- @return string
local function get_hash_color(sha)
  local r, g, b = sha:match('(%x)%x(%x)%x(%x)')
  assert(r and g and b, 'Invalid hash color')
  local color = mod(r) * 0x10000 + mod(g) * 0x100 + mod(b)

  if hash_colors[color] then
    return hash_colors[color]
  end

  local hl_name = string.format('GitSignsBlameColor.%s%s%s', r, g, b)
  api.nvim_set_hl(0, hl_name, { fg = color })
  hash_colors[color] = hl_name

  return hl_name
end

---@param amount integer
---@param text string
---@return string
local function lalign(amount, text)
  local len = vim.fn.strdisplaywidth(text)
  return text .. string.rep(' ', math.max(0, amount - len))
end

local chars = {
  first = '┍',
  mid = '│',
  last = '┕',
  single = '╺',
}

local M = {}

--- @param blame Gitsigns.CacheEntry.Blame
--- @param win integer
--- @param main_win integer
--- @param buf_sha? string
--- @return table<integer,true> commit_lines
local function render(blame, win, main_win, buf_sha)
  local max_author_len = 0
  local entries = blame.entries

  for _, b in pairs(entries) do
    max_author_len = math.max(max_author_len, vim.fn.strdisplaywidth(b.commit.author))
  end

  local lines = {} --- @type string[]
  local last_sha --- @type string?
  local cnt = 0
  local commit_lines = {} --- @type table<integer,true>

  for i, b in pairs(entries) do
    local commit = b.commit
    local sha = commit.abbrev_sha
    local next_sha = entries[i + 1] and entries[i + 1].commit.abbrev_sha or nil
    if sha == last_sha then
      cnt = cnt + 1
      local c = sha == next_sha and chars.mid or chars.last
      lines[i] = cnt == 1 and ('%s %s'):format(c, commit.summary) or c
      if commit_lines[i - 1] then
        assert(lines[i - 1], 'Previous line should exist')
        lines[i - 1] = chars.first .. lines[i - 1]:sub(#chars.single + 1)
      end
    else
      cnt = 0
      commit_lines[i] = true
      lines[i] = ('%s %s %s %s'):format(
        chars.single,
        sha,
        lalign(max_author_len, commit.author),
        util.expand_format('<author_time>', commit)
      )
    end
    last_sha = sha
  end

  local win_width = #lines[1]
  api.nvim_win_set_width(win, win_width + 1)

  local bufnr = api.nvim_win_get_buf(win)
  local main_buf = api.nvim_win_get_buf(main_win)

  api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  local min_time, max_time = assert(cache[main_buf]):get_blame_times()

  -- Apply highlights
  for i, blame_info in ipairs(entries) do
    local hash_hl = get_hash_color(blame_info.commit.abbrev_sha)

    api.nvim_buf_set_extmark(bufnr, ns, i - 1, 0, {
      end_col = commit_lines[i] and 12 or 1,
      hl_group = hash_hl,
    })

    api.nvim_buf_set_extmark(bufnr, ns, i - 1, 0, {
      virt_text_win_col = win_width,
      virt_text = {
        {
          '┃',
          get_temp_hl(min_time, max_time, blame_info.commit.author_time, 0.5, true),
        },
      },
    })

    if not commit_lines[i] then
      api.nvim_buf_set_extmark(bufnr, ns, i - 1, 2, {
        end_row = i,
        end_col = 0,
        hl_group = 'Comment',
      })
    end

    if buf_sha == blame_info.commit.sha then
      hl_line(bufnr, ns, i, '@markup.italic')
    end
  end

  return commit_lines
end

--- @async
--- @param opts Gitsigns.BlameOpts?
--- @param blame table<integer,Gitsigns.BlameInfo?>
--- @param win integer
--- @param revision? string
--- @param parent? boolean
local function reblame(opts, blame, win, revision, parent)
  local blm_win = api.nvim_get_current_win()
  local lnum = api.nvim_win_get_cursor(blm_win)[1]
  local sha = assert(blame[lnum]).commit.sha
  if parent then
    sha = sha .. '^'
  end
  if sha == revision then
    return
  end

  vim.cmd.quit()
  api.nvim_set_current_win(win)

  local did_attach = require('gitsigns.actions.diffthis').show(nil, sha)
  if not did_attach then
    return
  end
  async.schedule()
  M.blame(opts)
end

--- @async
--- @param win integer
--- @param bwin integer
--- @param open 'vsplit'|'tabnew'
--- @param bcache Gitsigns.CacheEntry
local function show_commit(win, bwin, open, bcache)
  local cursor = api.nvim_win_get_cursor(bwin)[1]
  local blame = assert(bcache.blame)
  local sha = assert(blame.entries[cursor]).commit.sha
  api.nvim_set_current_win(win)
  require('gitsigns.actions.show_commit')(sha, open)
end

--- @param augroup integer
--- @param wins integer[]
local function sync_cursors(augroup, wins)
  local cursor_save --- @type integer?

  ---@param w integer
  local function sync_cursor(w)
    local b = api.nvim_win_get_buf(w)
    api.nvim_create_autocmd('BufLeave', {
      buffer = b,
      group = augroup,
      callback = function()
        if api.nvim_win_is_valid(w) then
          cursor_save = api.nvim_win_get_cursor(w)[1]
        end
      end,
    })

    api.nvim_create_autocmd('BufEnter', {
      group = augroup,
      buffer = b,
      callback = function()
        if not api.nvim_win_is_valid(w) then
          return
        end
        local cur_cursor, cur_cursor_col = unpack(api.nvim_win_get_cursor(w))
        if cursor_save and cursor_save ~= cur_cursor then
          api.nvim_win_set_cursor(w, { cursor_save, vim.o.startofline and 0 or cur_cursor_col })
        end
      end,
    })
  end

  for _, w in ipairs(wins) do
    sync_cursor(w)
  end
end

--- @param name string
--- @param items [string, string][]
local function menu(name, items)
  local max_len = 0
  for _, item in ipairs(items) do
    max_len = math.max(max_len, #item[1]) --- @type integer
  end

  for _, item in ipairs(items) do
    local item_nm, action = item[1], item[2]
    local pad = string.rep(' ', max_len - #item_nm)
    local lhs = string.format('%s%s (%s)', item_nm, pad, action):gsub(' ', [[\ ]])
    local cmd = string.format('nmenu <silent> ]%s.%s %s', name, lhs, action)

    vim.cmd(cmd)
  end
end

--- @param bufnr integer
--- @param blm_win integer
--- @param blame table<integer,Gitsigns.BlameInfo?>
--- @param commit_lines table<integer,true>
local function on_cursor_moved(bufnr, blm_win, blame, commit_lines)
  local blm_bufnr = api.nvim_get_current_buf()
  local lnum = api.nvim_win_get_cursor(blm_win)[1]
  local cur_sha = assert(blame[lnum]).commit.abbrev_sha
  for i, info in pairs(blame) do
    if info.commit.abbrev_sha == cur_sha then
      hl_line(blm_bufnr, ns_hl, i, 'CursorLine')
      hl_line(blm_bufnr, ns_hl, i, '@markup.strong')
      hl_line(bufnr, ns_hl, i, 'CursorLine')
    end
  end

  if commit_lines[lnum] and commit_lines[lnum + 1] then
    local blame_info = assert(blame[lnum])
    local hash_hl = get_hash_color(blame_info.commit.abbrev_sha)
    api.nvim_buf_set_extmark(blm_bufnr, ns_hl, lnum - 1, 0, {
      virt_text = { { chars.first, hash_hl } },
      virt_text_pos = 'overlay',
    })
    api.nvim_buf_set_extmark(blm_bufnr, ns_hl, lnum - 1, 0, {
      virt_lines = {
        { { chars.last, hash_hl }, { ' ' }, { blame_info.commit.summary, 'Comment' } },
      },
    })

    local fillchar = string.rep(vim.opt.fillchars:get().diff or '-', 1000)

    api.nvim_buf_set_extmark(bufnr, ns_hl, lnum - 1, 0, {
      virt_lines = { { { fillchar, 'Comment' } } },
      virt_lines_leftcol = true,
    })
  end
end

--- @async
--- @param bufnr integer
--- @param blm_win integer
--- @param blame table<integer,Gitsigns.BlameInfo?>
local function diff(bufnr, blm_win, blame)
  local lnum = api.nvim_win_get_cursor(blm_win)[1]
  local info = assert(blame[lnum])

  vim.cmd.tabnew()
  api.nvim_set_current_buf(bufnr)
  require('gitsigns.actions.diffthis').show(bufnr, info.commit.sha, info.filename)
  if info.previous_sha then
    require('gitsigns.actions').diffthis(info.previous_sha)
  end
end

--- @param mode string
--- @param lhs string
--- @param cb fun()
--- @param opts vim.keymap.set.Opts
local function pmap(mode, lhs, cb, opts)
  opts.expr = true

  vim.keymap.set(mode, lhs, function()
    vim.schedule(function()
      cb()
    end)
    return '<esc>'
  end, opts)
end

--- @async
--- @param opts Gitsigns.BlameOpts?
function M.blame(opts)
  local __FUNC__ = 'blame'
  local bufnr = api.nvim_get_current_buf()
  local win = api.nvim_get_current_win()
  local bcache = cache[bufnr]
  if not bcache then
    log.dprint('Not attached')
    return
  end

  local lnum = nil
  bcache:get_blame(lnum, opts)
  local blame = assert(bcache.blame)

  -- Save position to align 'scrollbind'
  local top = vim.fn.line('w0') + vim.wo.scrolloff
  local current = vim.fn.line('.')

  vim.cmd.vsplit({ mods = { keepalt = true, split = 'aboveleft' } })
  local blm_win = api.nvim_get_current_win()

  local blm_bufnr = api.nvim_create_buf(false, true)
  api.nvim_win_set_buf(blm_win, blm_bufnr)
  api.nvim_buf_set_name(blm_bufnr, (bcache:get_rev_bufname():gsub('^gitsigns:', 'gitsigns-blame:')))

  local commit_lines = render(blame, blm_win, win, bcache.git_obj.revision)

  local blm_bo = vim.bo[blm_bufnr]
  blm_bo.buftype = 'nofile'
  blm_bo.bufhidden = 'wipe'
  blm_bo.modifiable = false
  blm_bo.filetype = 'gitsigns-blame'

  local blm_wlo = vim.wo[blm_win][0]
  blm_wlo.foldcolumn = '0'
  blm_wlo.foldenable = false
  blm_wlo.number = false
  blm_wlo.relativenumber = false
  blm_wlo.scrollbind = true
  blm_wlo.signcolumn = 'no'
  blm_wlo.spell = false
  blm_wlo.winfixwidth = true
  blm_wlo.wrap = false
  blm_wlo.list = false

  if vim.wo[win].winbar ~= '' and blm_wlo.winbar == '' then
    local name = api.nvim_buf_get_name(bufnr)
    blm_wlo.winbar = vim.fn.fnamemodify(name, ':.')
  end

  if vim.fn.exists('&winfixbuf') == 1 then
    blm_wlo.winfixbuf = true
  end

  vim.cmd(tostring(top))
  vim.cmd('normal! zt')
  vim.cmd(tostring(current))
  vim.cmd('normal! 0')

  local cur_wlo = vim.wo[win][0]
  local cur_orig_wlo = { cur_wlo.foldenable, cur_wlo.scrollbind, cur_wlo.wrap }
  cur_wlo.foldenable = false
  cur_wlo.scrollbind = true
  cur_wlo.wrap = false

  vim.cmd.redraw()
  vim.cmd.syncbind()

  vim.keymap.set('n', '<CR>', function()
    vim.cmd.popup(']GitsignsBlame')
  end, {
    desc = 'Open blame context menu',
    buffer = blm_bufnr,
  })

  pmap('n', 'r', function()
    async.run(reblame, opts, blame.entries, win, bcache.git_obj.revision):raise_on_error()
  end, {
    desc = 'Reblame at commit',
    buffer = blm_bufnr,
  })

  pmap('n', 'd', function()
    async.run(diff, bufnr, blm_win, blame.entries):raise_on_error()
  end, {
    desc = 'Diff (tab)',
    buffer = blm_bufnr,
  })

  pmap('n', 'R', function()
    async.run(reblame, opts, blame.entries, win, bcache.git_obj.revision, true):raise_on_error()
  end, {
    desc = 'Reblame at commit parent',
    buffer = blm_bufnr,
  })

  pmap('n', 's', function()
    async.run(show_commit, win, blm_win, 'vsplit', bcache):raise_on_error()
  end, {
    desc = 'Show commit in a vertical split',
    buffer = blm_bufnr,
  })

  pmap('n', 'S', function()
    async.run(show_commit, win, blm_win, 'tabnew', bcache):raise_on_error()
  end, {
    desc = 'Show commit in a new tab',
    buffer = blm_bufnr,
  })

  menu('GitsignsBlame', {
    { 'Reblame at commit', 'r' },
    { 'Reblame at commit parent', 'R' },
    { 'Diff (tab)', 'd' },
    { 'Show commit (vsplit)', 's' },
    { '            (tab)', 'S' },
  })

  local group = api.nvim_create_augroup('GitsignsBlame', {})

  api.nvim_create_autocmd({ 'BufHidden', 'QuitPre' }, {
    buffer = bufnr,
    group = group,
    once = true,
    callback = function()
      if api.nvim_win_is_valid(blm_win) then
        api.nvim_win_close(blm_win, true)
      end
    end,
  })

  api.nvim_create_autocmd({ 'CursorMoved', 'BufLeave' }, {
    buffer = blm_bufnr,
    group = group,
    callback = function()
      api.nvim_buf_clear_namespace(blm_bufnr, ns_hl, 0, -1)
      if api.nvim_buf_is_valid(bufnr) then
        api.nvim_buf_clear_namespace(bufnr, ns_hl, 0, -1)
      end
    end,
  })

  -- Highlight the same commit under the cursor
  api.nvim_create_autocmd('CursorMoved', {
    buffer = blm_bufnr,
    group = group,
    callback = function()
      on_cursor_moved(bufnr, blm_win, blame.entries, commit_lines)
    end,
  })

  api.nvim_create_autocmd('WinClosed', {
    pattern = tostring(blm_win),
    group = group,
    callback = function()
      api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
      if api.nvim_win_is_valid(win) then
        cur_wlo.foldenable, cur_wlo.scrollbind, cur_wlo.wrap = unpack(cur_orig_wlo)
      end
    end,
  })

  sync_cursors(group, { win, blm_win })
end

return M
