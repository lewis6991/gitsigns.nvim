local async = require('gitsigns.async')
local cache = require('gitsigns.cache').cache
local log = require('gitsigns.debug.log')
local util = require('gitsigns.util')

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
  --- @diagnostic disable-next-line: missing-parameter
  local len = vim.str_utfindex(text)
  return text .. string.rep(' ', math.max(0, amount - len))
end

local chars = {
  first = '┍',
  mid = '│',
  last = '┕',
  single = '╺',
}

local M = {}

--- @param blame table<integer,Gitsigns.BlameInfo?>
--- @param win integer
--- @param main_win integer
--- @param buf_sha? string
local function render(blame, win, main_win, buf_sha)
  local max_author_len = 0

  for _, blame_info in pairs(blame) do
    --- @diagnostic disable-next-line: missing-parameter
    max_author_len = math.max(max_author_len, (vim.str_utfindex(blame_info.commit.author)))
  end

  local lines = {} --- @type string[]
  local last_sha --- @type string?
  local cnt = 0
  local commit_lines = {} --- @type table<integer,true>
  for i, hl in pairs(blame) do
    local sha = hl.commit.abbrev_sha
    local next_sha = blame[i + 1] and blame[i + 1].commit.abbrev_sha or nil
    if sha == last_sha then
      cnt = cnt + 1
      local c = sha == next_sha and chars.mid or chars.last
      lines[i] = cnt == 1 and string.format('%s %s', c, hl.commit.summary) or c
    else
      cnt = 0
      commit_lines[i] = true
      lines[i] = string.format(
        '%s %s %s %s',
        chars.first,
        sha,
        lalign(max_author_len, hl.commit.author),
        util.expand_format('<author_time>', hl.commit)
      )
    end
    last_sha = sha
  end

  local win_width = #lines[1]
  api.nvim_win_set_width(win, win_width + 1)

  local bufnr = api.nvim_win_get_buf(win)
  local main_buf = api.nvim_win_get_buf(main_win)

  api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  -- Apply highlights
  for i, blame_info in ipairs(blame) do
    local hash_color = get_hash_color(blame_info.commit.abbrev_sha)

    api.nvim_buf_set_extmark(bufnr, ns, i - 1, 0, {
      end_col = commit_lines[i] and 12 or 1,
      hl_group = hash_color,
    })

    if commit_lines[i] then
      local width = #(assert(lines[i]))
      api.nvim_buf_set_extmark(bufnr, ns, i - 1, width - 10, {
        end_col = width,
        hl_group = 'Title',
      })
    else
      api.nvim_buf_set_extmark(bufnr, ns, i - 1, 2, {
        end_row = i,
        end_col = 0,
        hl_group = 'Comment',
      })
    end

    if buf_sha == blame_info.commit.sha then
      api.nvim_buf_set_extmark(bufnr, ns, i - 1, 0, {
        line_hl_group = '@markup.italic',
      })
    end

    if commit_lines[i] and commit_lines[i + 1] then
      api.nvim_buf_set_extmark(bufnr, ns, i - 1, 0, {
        virt_lines = {
          { { chars.last, hash_color }, { ' ' }, { blame_info.commit.summary, 'Comment' } },
        },
      })

      local fillchar = string.rep(vim.opt.fillchars:get().diff or '-', 1000)

      api.nvim_buf_set_extmark(main_buf, ns, i - 1, 0, {
        virt_lines = { { { fillchar, 'Comment' } } },
        virt_lines_leftcol = true,
      })
    end
  end
end

--- @param blame table<integer,Gitsigns.BlameInfo?>
--- @param win integer
--- @param revision? string
--- @param parent? boolean
local function reblame(blame, win, revision, parent)
  local blm_win = api.nvim_get_current_win()
  local lnum = unpack(api.nvim_win_get_cursor(blm_win))
  local sha = assert(blame[lnum]).commit.sha
  if parent then
    sha = sha .. '^'
  end
  if sha == revision then
    return
  end

  vim.cmd.quit()
  api.nvim_set_current_win(win)

  require('gitsigns').show(
    sha,
    vim.schedule_wrap(function()
      local bufnr = api.nvim_get_current_buf()
      local ok = vim.wait(1000, function()
        return cache[bufnr] ~= nil
      end)
      if not ok then
        error('Timeout waiting for attach')
      end
      async.arun(M.blame):raise_on_error()
    end)
  )
end

--- @param win integer
--- @param open 'vsplit'|'tabnew'
--- @param bcache Gitsigns.CacheEntry
local show_commit = async.async(function(win, open, bcache)
  local cursor = api.nvim_win_get_cursor(win)[1]
  local blame = assert(bcache.blame)
  local sha = assert(blame[cursor]).commit.sha
  local res = bcache.git_obj.repo:command({ 'show', sha })
  async.schedule()
  local buffer_name = bcache:get_rev_bufname(sha, true)
  local commit_buf = nil
  -- find preexisting commit buffer or create a new one
  for _, bufnr in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_get_name(bufnr) == buffer_name then
      commit_buf = bufnr
      break
    end
  end
  if commit_buf == nil then
    commit_buf = api.nvim_create_buf(true, true)
    api.nvim_buf_set_name(commit_buf, buffer_name)
    api.nvim_buf_set_lines(commit_buf, 0, -1, false, res)
  end
  vim.cmd[open]({ mods = { keepalt = true } })
  api.nvim_win_set_buf(0, commit_buf)
  vim.bo[commit_buf].filetype = 'git'
  vim.bo[commit_buf].bufhidden = 'wipe'
end)

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
          cursor_save = unpack(api.nvim_win_get_cursor(w))
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
function M.blame()
  local __FUNC__ = 'blame'
  local bufnr = api.nvim_get_current_buf()
  local win = api.nvim_get_current_win()
  local bcache = cache[bufnr]
  if not bcache then
    log.dprint('Not attached')
    return
  end

  bcache:get_blame()
  local blame = assert(bcache.blame)

  -- Save position to align 'scrollbind'
  local top = vim.fn.line('w0') + vim.wo.scrolloff
  local current = vim.fn.line('.')

  vim.cmd.vsplit({ mods = { keepalt = true, split = 'aboveleft' } })
  local blm_win = api.nvim_get_current_win()

  local blm_bufnr = api.nvim_create_buf(false, true)
  api.nvim_win_set_buf(blm_win, blm_bufnr)

  local revision = bcache.git_obj.revision

  render(blame, blm_win, win, revision)

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

  if vim.wo[win].winbar ~= '' and blm_wlo.winbar == '' then
    local name = api.nvim_buf_get_name(bufnr)
    blm_wlo.winbar = vim.fn.fnamemodify(name, ':.')
  end

  if vim.fn.exists('&winfixbuf') then
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
    reblame(blame, win, bcache.git_obj.revision)
  end, {
    desc = 'Reblame at commit',
    buffer = blm_bufnr,
  })

  pmap('n', 'R', function()
    reblame(blame, win, bcache.git_obj.revision, true)
  end, {
    desc = 'Reblame at commit parent',
    buffer = blm_bufnr,
  })

  pmap('n', 's', function()
    show_commit(blm_win, 'vsplit', bcache)
  end, {
    desc = 'Show commit in a vertical split',
    buffer = blm_bufnr,
  })

  pmap('n', 'S', function()
    show_commit(blm_win, 'tabnew', bcache)
  end, {
    desc = 'Show commit in a new tab',
    buffer = blm_bufnr,
  })

  menu('GitsignsBlame', {
    { 'Reblame at commit', 'r' },
    { 'Reblame at commit parent', 'R' },
    { 'Show commit (vsplit)', 's' },
    { '            (tab)', 'S' },
  })

  local group = api.nvim_create_augroup('GitsignsBlame', {})

  api.nvim_create_autocmd({ 'CursorMoved', 'BufLeave' }, {
    buffer = blm_bufnr,
    group = group,
    callback = function()
      api.nvim_buf_clear_namespace(blm_bufnr, ns_hl, 0, -1)
      api.nvim_buf_clear_namespace(bufnr, ns_hl, 0, -1)
    end,
  })

  -- Highlight the same commit under the cursor
  api.nvim_create_autocmd('CursorMoved', {
    buffer = blm_bufnr,
    group = group,
    callback = function()
      local cursor = unpack(api.nvim_win_get_cursor(blm_win))
      local cur_sha = assert(blame[cursor]).commit.abbrev_sha
      for i, info in pairs(blame) do
        if info.commit.abbrev_sha == cur_sha then
          api.nvim_buf_set_extmark(blm_bufnr, ns_hl, i - 1, 0, {
            line_hl_group = '@markup.strong',
          })
        end
      end
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
