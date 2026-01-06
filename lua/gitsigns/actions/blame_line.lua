local Hunks = require('gitsigns.hunks')
local cache = require('gitsigns.cache').cache
local config = require('gitsigns.config').config
local log = require('gitsigns.debug.log')
local popup = require('gitsigns.popup')
local run_diff = require('gitsigns.diff')
local util = require('gitsigns.util')

local api = vim.api

--- @async
--- @param repo Gitsigns.Repo
--- @param info Gitsigns.BlameInfoPublic
--- @return Gitsigns.Hunk.Hunk hunk
--- @return integer hunk_index
--- @return integer num_hunks
--- @return integer? guess_offset If the hunk was not found at the exact line,
---                               return the offset from the original line to the
---                               hunk start.
local function get_blame_hunk(repo, info)
  local a = repo:get_show_text(info.previous_sha .. ':' .. info.previous_filename)
  local b = repo:get_show_text(info.sha .. ':' .. info.filename)
  local hunks = run_diff(a, b, false)
  local hunk, i = Hunks.find_hunk(info.orig_lnum, hunks)
  if hunk and i then
    return hunk, i, #hunks
  end

  -- git-blame output is not always correct (see #1332)
  -- Find the closest hunk to the original line
  log.dprintf('Could not find hunk using hunk info %s', vim.inspect(info))

  local i_next = Hunks.find_nearest_hunk(info.orig_lnum, hunks, 'next')
  local i_prev = Hunks.find_nearest_hunk(info.orig_lnum, hunks, 'prev')

  if i_next and i_prev then
    -- if there is hunk before and after, find the closest
    local dist_n = math.abs(assert(hunks[i_next]).added.start - info.orig_lnum)
    local dist_p = math.abs(assert(hunks[i_prev]).added.start - info.orig_lnum)
    i = dist_n < dist_p and i_next or i_prev
  else
    i = assert(i_next or i_prev, 'no hunks in commit')
  end

  hunk = assert(hunks[i])
  return hunk, i, #hunks, hunk.added.start - info.orig_lnum
end

--- @async
--- @param repo Gitsigns.Repo
--- @param sha string
--- @return Gitsigns.LineSpec
local function create_commit_msg_body_linespec(repo, sha)
  local body0 = repo:command({ 'show', '-s', '--format=%B', sha }, { text = true })
  local body = table.concat(body0, '\n')
  return { { body, 'NormalFloat' } }
end

--- @async
--- @param info Gitsigns.BlameInfoPublic
--- @param repo Gitsigns.Repo
--- @param fileformat string
--- @return Gitsigns.LineSpec[]
local function create_blame_hunk_linespec(repo, info, fileformat)
  if not (info.previous_sha and info.previous_filename) then
    return { { { 'File added in commit', 'Title' } } }
  end

  --- @type Gitsigns.LineSpec[]
  local ret = {}
  local hunk, hunk_no, num_hunks, guess_offset = get_blame_hunk(repo, info)

  local hunk_title = {
    { ('Hunk %d of %d'):format(hunk_no, num_hunks), 'Title' },
    { ' ' .. hunk.head, 'LineNr' },
  }

  if guess_offset then
    hunk_title[#hunk_title + 1] = {
      (' (guessed: %s%d offset from original line)'):format(
        guess_offset >= 0 and '+' or '',
        guess_offset
      ),
      'WarningMsg',
    }
  end

  ret[#ret + 1] = hunk_title
  vim.list_extend(ret, Hunks.linespec_for_hunk(hunk, fileformat))
  return ret
end

--- @async
--- @param full boolean? Whether to show the full commit message and hunk
--- @param result Gitsigns.BlameInfoPublic
--- @param repo Gitsigns.Repo
--- @param fileformat string
--- @param with_gh boolean
--- @return Gitsigns.LineSpec[]
local function create_blame_linespec(full, result, repo, fileformat, with_gh)
  local is_committed = result.sha and tonumber('0x' .. result.sha) ~= 0

  if not is_committed then
    return {
      { { result.author, 'Label' } },
    }
  end

  local gh --- @module 'gitsigns.gh'?
  if config.gh and with_gh then
    gh = require('gitsigns.gh')
  end

  local commit_url = gh and gh.commit_url(result.sha, repo.toplevel) or nil

  --- @type Gitsigns.LineSpec
  local title = {
    { result.abbrev_sha, 'Directory', commit_url },
    { ' ', 'NormalFloat' },
  }

  if gh then
    vim.list_extend(title, gh.create_pr_linespec(result.sha, repo.toplevel))
  end

  vim.list_extend(title, {
    { result.author .. ' ', 'MoreMsg' },
    { util.expand_format('(<author_time:%Y-%m-%d %H:%M>)', result), 'Label' },
    { ':', 'NormalFloat' },
  })

  --- @type Gitsigns.LineSpec[]
  local ret = { title }

  if not full then
    ret[#ret + 1] = { { result.summary, 'NormalFloat' } }
    return ret
  end

  ret[#ret + 1] = create_commit_msg_body_linespec(repo, result.sha)
  vim.list_extend(ret, create_blame_hunk_linespec(repo, result, fileformat))

  return ret
end

--- @class (exact) Gitsigns.LineBlameOpts : Gitsigns.BlameOpts
--- @field full? boolean

--- @async
--- @param opts Gitsigns.LineBlameOpts?
return function(opts)
  if popup.focus_open('blame') then
    return
  end

  opts = opts or {}

  local bufnr = api.nvim_get_current_buf()
  local bcache = cache[bufnr]
  if not bcache then
    return
  end

  local loading = vim.defer_fn(function()
    popup.create({ { { 'Loading...', 'Title' } } }, config.preview_config)
  end, 1000)

  if not bcache:schedule() then
    return
  end

  local fileformat = vim.bo[bufnr].fileformat
  local lnum = api.nvim_win_get_cursor(0)[1]
  local popup_winid, popup_bufnr
  ---@async
  local function is_stale()
    return not bcache:schedule()
      or api.nvim_get_current_buf() ~= popup_bufnr
        and (api.nvim_get_current_buf() ~= bufnr or api.nvim_win_get_cursor(0)[1] ~= lnum)
  end
  local info = bcache:get_blame(lnum, opts)
  pcall(function()
    loading:close()
  end)

  if is_stale() then
    return
  end

  local result = util.convert_blame_info(assert(info))

  local blame_linespec =
    create_blame_linespec(opts.full, result, bcache.git_obj.repo, fileformat, false)

  if is_stale() then
    return
  end

  popup_winid, popup_bufnr = popup.create(blame_linespec, config.preview_config, 'blame')

  blame_linespec = create_blame_linespec(opts.full, result, bcache.git_obj.repo, fileformat, true)

  if is_stale() then
    return
  end

  if api.nvim_win_is_valid(popup_winid) and api.nvim_buf_is_valid(popup_bufnr) then
    popup.update(popup_winid, popup_bufnr, blame_linespec, config.preview_config)
  end
end
