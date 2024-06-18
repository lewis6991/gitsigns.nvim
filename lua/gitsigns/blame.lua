local api = vim.api

local cache = require('gitsigns.cache').cache
local util = require('gitsigns.util')
local async = require('gitsigns.async')

local log = require('gitsigns.debug.log')
local dprint = log.dprint

local hash_colors = {} --- @type table<string,string>

local ns = api.nvim_create_namespace('gitsigns_blame_win')
local ns_hl = api.nvim_create_namespace('gitsigns_blame_win_hl')

--- @param sha string
--- @return string
local function get_hash_color(sha)
  if hash_colors[sha] then
    return hash_colors[sha]
  end

  local r0, g0, b0 = sha:match('(%x)%x(%x)%x(%x)')
  local color = tonumber(string.format('%s0%s0%s0', r0, g0, b0), 16)

  local hl_name = 'GitSignsBlameHash' .. sha
  api.nvim_set_hl(0, hl_name, { fg = color })
  hash_colors[sha] = hl_name

  return hl_name
end

---@param amount integer
---@param text string
---@return string
local function lalign(amount, text)
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
--- @param buf_sha string
local function render(blame, win, main_win, buf_sha)
  local max_author_len = 0

  for _, blame_info in pairs(blame) do
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
      api.nvim_buf_set_extmark(bufnr, ns, i - 1, win_width - 10, {
        end_col = win_width,
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
          { { chars.last, hash_color }, { ' ' }, { blame[i].commit.summary, 'Comment' } },
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
local function reblame(blame, win, revision)
  local blm_win = api.nvim_get_current_win()
  local lnum = unpack(api.nvim_win_get_cursor(blm_win))
  local sha = blame[lnum].commit.sha
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
      async.run(M.blame)
    end)
  )
end

--- @param sha string
--- @param git_obj Gitsigns.GitObj
local show_commit = async.create(2, function(sha, git_obj)
  local res = git_obj:command({ 'show', sha })
  async.scheduler()
  local commit_buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(commit_buf, 0, -1, false, res)
  vim.cmd.vsplit({ mods = { keepalt = true } })
  api.nvim_win_set_buf(0, commit_buf)
  vim.bo[commit_buf].filetype = 'git'
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
        cursor_save = unpack(api.nvim_win_get_cursor(w))
      end,
    })

    api.nvim_create_autocmd('BufEnter', {
      group = augroup,
      buffer = b,
      callback = function()
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

--- @async
M.blame = function()
  local __FUNC__ = 'blame'
  local bufnr = api.nvim_get_current_buf()
  local win = api.nvim_get_current_win()
  local bcache = cache[bufnr]
  if not bcache then
    dprint('Not attached')
    return
  end

  local blame = bcache:run_blame(nil, { rev = bcache.git_obj.revision })
  if not blame then
    dprint('No blame info')
    return
  end

  -- Save position to align 'scrollbind'
  local top = vim.fn.line('w0') + vim.wo.scrolloff
  local current = vim.fn.line('.')

  vim.cmd.vsplit({ mods = { keepalt = true, split = 'aboveleft' } })
  local blm_win = api.nvim_get_current_win()

  local blm_bufnr = api.nvim_create_buf(false, true)
  api.nvim_win_set_buf(blm_win, blm_bufnr)

  render(blame, blm_win, win, bcache.git_obj.revision)

  local blm_bo = vim.bo[blm_bufnr]
  blm_bo.buftype = 'nofile'
  blm_bo.modifiable = false

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

  if vim.fn.exists('&winfixbuf') then
    blm_wlo.winfixbuf = true
  end

  vim.cmd(tostring(top))
  vim.cmd('normal! zt')
  vim.cmd(tostring(current))

  local cur_wlo = vim.wo[win][0]
  cur_wlo.foldenable = false
  cur_wlo.scrollbind = true
  cur_wlo.wrap = false

  vim.cmd.redraw()
  vim.cmd.syncbind()

  vim.keymap.set('n', '<CR>', function()
    vim.cmd.popup('GitsignsBlame')
  end, {
    desc = 'Open blame context menu',
    buffer = blm_bufnr,
  })

  vim.keymap.set('n', 'r', function()
    reblame(blame, win, bcache.git_obj.revision)
  end, {
    desc = 'Reblame at commit',
    buffer = blm_bufnr,
  })

  vim.keymap.set('n', 's', function()
    local cursor = api.nvim_win_get_cursor(blm_win)[1]
    local sha = blame[cursor].commit.sha
    show_commit(sha, bcache.git_obj)
  end, {
    desc = 'Show commit',
    buffer = blm_bufnr,
  })

  vim.cmd([[
   :nnoremenu <silent> GitsignsBlame.Reblame\ at\ commit\ \ (r)        r
   :nnoremenu <silent> GitsignsBlame.Show\ commit\ \ \ \ \ \ \ \ (s)   s
  ]])

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
      local cur_sha = blame[cursor].commit.abbrev_sha
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
    end,
  })

  sync_cursors(group, { win, blm_win })
end

return M
