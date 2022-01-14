local void = require('plenary.async.async').void
local awrap = require('plenary.async.async').wrap

local gs_cache = require('gitsigns.cache')
local CacheEntry = gs_cache.CacheEntry
local cache = gs_cache.cache

local signs             = require('gitsigns.signs')
local Sign              = signs.Sign

local Status            = require("gitsigns.status")

local debounce_trailing = require('gitsigns.debounce').debounce_trailing
local throttle_by_id    = require('gitsigns.debounce').throttle_by_id
local gs_debug          = require("gitsigns.debug")
local dprint            = gs_debug.dprint
local dprintf           = gs_debug.dprintf
local eprint            = gs_debug.eprint
local subprocess        = require('gitsigns.subprocess')
local util              = require('gitsigns.util')

local gs_hunks          = require("gitsigns.hunks")
local Hunk              = gs_hunks.Hunk

local setup_highlight   = require('gitsigns.highlight').setup_highlight

local config         = require('gitsigns.config').config

local api = vim.api

local record M
  update           : function(integer, CacheEntry)
  update_debounced : function(integer, CacheEntry)
  apply_win_signs  : function(bufnr: integer, pending: {integer:Sign}, top: integer, bot: integer)
  on_lines         : function(buf: integer, last_orig: integer, last_new: integer): boolean

  apply_word_diff: function(buf: integer, row: integer)

  setup: function()
  setup_signs_and_highlights: function(redefine: boolean)
end

local schedule_if_buf_valid = function(buf: integer, cb: function)
  vim.schedule(function()
    if vim.api.nvim_buf_is_valid(buf) then
      cb()
    end
  end)
end

local scheduler_if_buf_valid = awrap(schedule_if_buf_valid, 2)

function M.apply_win_signs(bufnr: integer, pending: {integer:Sign}, top: integer, bot: integer)
  -- If called without top or bot, then assume this is the first call after
  -- clearing all the signs
  local first_apply = top == nil

  -- Just apply to signs visible in window
  top = top or vim.fn.line('w0')
  bot = bot or vim.fn.line('w$')

  local scheduled: {integer:Sign} = {}

  local function schedule_sign(n: integer, _: any)
    if n and pending[n] then
      scheduled[n] = pending[n]
      pending[n] = nil
    end
  end

  for lnum = top, bot do
    schedule_sign(lnum)
  end

  if first_apply then
    signs.remove(bufnr)  -- Remove all signs

    -- To stop the sign column width changing too much, if there are signs to be
    -- added but none of them are visible in the window, then make sure to add at
    -- least one sign. Only do this on the first call after an update when we all
    -- the signs have been cleared.
    schedule_sign(next(pending))
  end

  signs.add(config, bufnr, scheduled)

end

-- Speculate on future signs. It's not a big deal if we speculate incorrectly as
-- update() will overwrite all the signs anyway. This has noticeable effect on
-- large files and even makes small files feel very snappy.
--
-- Returns true if signs are added or removed
local function speculate_signs(buf: integer, last_orig: integer, last_new: integer): boolean
  if last_new < last_orig then
    -- Lines removed
    --
    -- Cannot do much here due to https://github.com/neovim/neovim/pull/12323
  elseif last_new > last_orig then
    -- Lines added

    if last_orig == 0 then
      -- Note: It seems that
      local placed = signs.get(buf, 1)[1]

      -- Add 'added' signs only if there wasn't a 'delete' sign above
      if not placed or not vim.startswith(placed, 'GitSignsTopDelete') then
        -- If lines are added, make sure to immediately add the signs
        for i = 1, last_new do
          signs.add(config, buf, {[i] = {type='add', count=0}})
        end
      else
        signs.remove(buf, 1)
      end
      return true
    else
      local placed = signs.get(buf, last_orig)[last_orig]

      -- Add 'added' signs only if there wasn't a 'delete' sign above
      if not placed or not vim.startswith(placed, 'GitSignsDelete') then
        -- If lines are added, make sure to immediately add the signs
        for i = last_orig+1, last_new do
          signs.add(config, buf, {[i] = {type='add', count=0}})
        end
        return true
      end
    end
  else
    -- Line change

    local placed = signs.get(buf, last_orig)[last_orig]

    -- add a 'change' sign if there are no other signs
    if not placed then
      signs.add(config, buf, {[last_orig] = {type='change', count=0}})
      return true
    end
  end
end

M.on_lines = function(buf: integer, last_orig: integer, last_new: integer): boolean
  local bcache = cache[buf]
  if not bcache then
    dprint('Cache for buffer was nil. Detaching')
    return true
  end

  -- Schedule sign speculation ortherwise CTRL-C in insert mode can cause a
  -- callback error. See #346
  schedule_if_buf_valid(buf, function()
    if speculate_signs(buf, last_orig, last_new) then
      -- Speculative signs are added immediately whereas updates are debounced and
      -- throttled for each buffer. If we perform two quick updates which result
      -- in a sign begin added then removed, we need to make sure speculative
      -- signs don't incorrectly persist. Example:
      --
      --   -> buffer change
      --      - speculative signs (#1)
      --      - update (#1)
      --   -> undo (quickly after buffer change)
      --      - speculative signs (#2)
      --      - update (#2)
      --
      -- Update #1 is dropped due to the debounce which results in update #2 not
      -- updating signs due to the hunks not changing. Since signs are never
      -- updated, the speculative signs #1 and #2 will persist.
      --
      -- To get around this, we just need to invalidate the hunks to force a sign
      -- refresh.
      bcache.hunks = nil
    end
  end)
  M.update_debounced(buf, cache[buf])
end

local ns = api.nvim_create_namespace('gitsigns')

M.apply_word_diff = function(bufnr: integer, row: integer)
  if not cache[bufnr] or not cache[bufnr].hunks then return end

  local lnum = row + 1
  local cols = #api.nvim_buf_get_lines(bufnr, lnum-1, lnum, false)[1]

  for _, hunk in ipairs(cache[bufnr].hunks) do
    if lnum >= hunk.start and lnum <= hunk.vend then
      local size = (#hunk.added.lines +#hunk.removed.lines) / 2
      local regions = require('gitsigns.diff_int').run_word_diff(hunk.removed.lines, hunk.added.lines)
      for _, region in ipairs(regions) do
        local line = region[1]
        if lnum == hunk.start + line - size - 1 then
          -- and vim.startswith(hunk.lines[line], '+') then
          local rtype, scol, ecol = region[2], region[3], region[4]
          if scol <= cols then
            if ecol > cols then
              ecol = cols
            elseif ecol == scol then
              -- Make sure region is at least 1 column width
              ecol = scol + 1
            end
            api.nvim_buf_set_extmark(bufnr, ns, row, scol-1, {
              end_col = ecol-1,
              hl_group = rtype == 'add'    and 'GitSignsAddLn'
                      or rtype == 'change' and 'GitSignsChangeLn'
                      or                       'GitSignsDeleteLn',
              ephemeral = true
            })
          end
        end
      end
      break
    end
  end
end

local ns_rm = api.nvim_create_namespace('gitsigns_removed')

local VIRT_LINE_LEN = 300

local function clear_deleted(bufnr: integer)
  local marks = api.nvim_buf_get_extmarks(bufnr, ns_rm, 0, -1, {})
  for _, mark in ipairs(marks as {{integer, integer, integer}}) do
    api.nvim_buf_del_extmark(bufnr, ns_rm, mark[1])
  end
end

local function show_deleted(bufnr: integer)
  local bcache = cache[bufnr]

   clear_deleted(bufnr)

   if not config.show_deleted then
     return
   end

  for _, hunk in ipairs(bcache.hunks) do
    local virt_lines = {}
    local do_word_diff = config.word_diff and #hunk.removed.lines == #hunk.added.lines

    for i, line in ipairs(hunk.removed.lines) do
      local vline = {}
      local last_ecol = 1

      if do_word_diff then
        local regions = require('gitsigns.diff_int').run_word_diff(
          {hunk.removed.lines[i]}, {hunk.added.lines[i]})

        for _, region in ipairs(regions) do
          local rline, scol, ecol = region[1], region[3], region[4]
          if rline > 1 then
            break
          end
          vline[#vline+1] = { line:sub(last_ecol, scol-1), config.signs.delete.linehl }
          vline[#vline+1] = { line:sub(scol, ecol-1), 'TermCursor'}
          last_ecol = ecol
        end
      end

      if #line > 0 then
        vline[#vline+1] = { line:sub(last_ecol, -1), config.signs.delete.linehl }
      end

      -- Add extra padding so the entire line is highlighted
      local padding = string.rep(' ', VIRT_LINE_LEN-#line)
      vline[#vline+1] = { padding, config.signs.delete.linehl }

      virt_lines[i] = vline
    end

    api.nvim_buf_set_extmark(bufnr, ns_rm, hunk.start-1, -1, {
      virt_lines       = virt_lines,
      virt_lines_above = hunk.type ~= 'delete',
    })
  end
end

local update_cnt = 0

local update0 = function(bufnr: integer, bcache: CacheEntry)
  local __FUNC__ = 'update'
  bcache = bcache or cache[bufnr]
  if not bcache then
    eprint('Cache for buffer '..bufnr..' was nil')
    return
  end
  local old_hunks = bcache.hunks
  bcache.hunks = nil

  scheduler_if_buf_valid(bufnr)
  local buftext = util.buf_lines(bufnr)
  local git_obj = bcache.git_obj

  -- Make sure these requires are done in the main event.
  -- See https://github.com/neovim/neovim/issues/15147
  local run_diff: function({string}, {string}, string, boolean): {Hunk}
  if config.diff_opts.internal then
    run_diff = require('gitsigns.diff_int').run_diff
  else
    run_diff = require('gitsigns.diff_ext').run_diff
  end

  if not bcache.compare_text or config._refresh_staged_on_update then
    bcache.compare_text = git_obj:get_show_text(bcache:get_compare_rev())
  end

  bcache.hunks = run_diff(bcache.compare_text, buftext,
    config.diff_opts.algorithm, config.diff_opts.indent_heuristic)

  scheduler_if_buf_valid(bufnr)
  if gs_hunks.compare_heads(bcache.hunks, old_hunks) then
    bcache.pending_signs = gs_hunks.process_hunks(bcache.hunks)

    -- Apply signs to the window. Other signs will be added by the decoration
    -- provider as they are drawn.
    M.apply_win_signs(bufnr, bcache.pending_signs)

    show_deleted(bufnr)
  end
  local summary = gs_hunks.get_summary(bcache.hunks)
  summary.head = git_obj.repo.abbrev_head
  Status:update(bufnr, summary)

  update_cnt = update_cnt + 1

  dprintf('updates: %s, jobs: %s', update_cnt, subprocess.job_cnt)
end


-- Ensure updates cannot be interleaved.
-- Since updates are asynchronous we need to make sure an update isn't performed
-- whilst another one is in progress. If this happens then schedule another
-- update after the current one has completed.
M.update = throttle_by_id(update0) as function(integer, CacheEntry)

M.setup = function()
  M.update_debounced = debounce_trailing(config.update_debounce, void(M.update)) as function(integer)
end

M.setup_signs_and_highlights = function(redefine: boolean)
  -- Define signs
  for t, sign_name in pairs(signs.sign_map) do
    local cs = config.signs[t]

    setup_highlight(cs.hl)

    if config.numhl then
      setup_highlight(cs.numhl)
    end

    if config.linehl or config.word_diff then
      setup_highlight(cs.linehl)
    end

    signs.define(sign_name, {
      texthl = cs.hl,
      text   = config.signcolumn and cs.text or nil,
      numhl  = config.numhl      and cs.numhl,
      linehl = config.linehl     and cs.linehl
    }, redefine)

  end
  if config.current_line_blame then
    setup_highlight('GitSignsCurrentLineBlame')
  end
end

return M
