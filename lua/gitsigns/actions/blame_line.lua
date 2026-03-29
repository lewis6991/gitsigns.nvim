local async = require('gitsigns.async')
local Hunks = require('gitsigns.hunks')
local HunkPreview = require('gitsigns.hunk_preview')
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
--- @return {hunk:Gitsigns.Hunk.Hunk,hunk_index:integer,num_hunks:integer,guess_offset?:integer,removed:string[],added:string[]}
local function get_blame_hunk(repo, info)
  local removed = repo:get_show_text(info.previous_sha .. ':' .. info.previous_filename)
  local added = repo:get_show_text(info.sha .. ':' .. info.filename)
  local hunks = run_diff(removed, added, false)
  local hunk, i = Hunks.find_hunk(info.orig_lnum, hunks)
  if hunk and i then
    return {
      hunk = hunk,
      hunk_index = i,
      num_hunks = #hunks,
      removed = removed,
      added = added,
    }
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
  return {
    hunk = hunk,
    hunk_index = i,
    num_hunks = #hunks,
    guess_offset = hunk.added.start - info.orig_lnum,
    removed = removed,
    added = added,
  }
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

--- @param result Gitsigns.BlameInfoPublic
--- @return boolean
local function is_committed(result)
  return result.sha and tonumber('0x' .. result.sha) ~= 0
end

--- @param preview {hunk:Gitsigns.Hunk.Hunk,hunk_index:integer,num_hunks:integer,guess_offset?:integer,removed:string[],added:string[]}
--- @return Gitsigns.LineSpec
local function create_blame_hunk_title(preview)
  local title = {
    { ('Hunk %d of %d'):format(preview.hunk_index, preview.num_hunks), 'Title' },
    { ' ' .. preview.hunk.head, 'LineNr' },
  }

  if preview.guess_offset then
    title[#title + 1] = {
      (' (guessed: %s%d offset from original line)'):format(
        preview.guess_offset >= 0 and '+' or '',
        preview.guess_offset
      ),
      'WarningMsg',
    }
  end

  return title
end

--- @async
--- @param bufnr integer
--- @param info Gitsigns.BlameInfoPublic
--- @param repo Gitsigns.Repo
--- @return Gitsigns.LineSpec[]
local function create_blame_hunk_linespec(bufnr, repo, info)
  if not (info.previous_sha and info.previous_filename) then
    return { { { 'File added in commit', 'Title' } } }
  end

  --- @type Gitsigns.LineSpec[]
  local ret = {}
  local preview = get_blame_hunk(repo, info)
  ret[#ret + 1] = create_blame_hunk_title(preview)

  if vim.in_fast_event() then
    -- Popup preview assembly can be triggered from fast events, but source
    -- preparation may wait and touch scratch buffers before capture.
    --- @diagnostic disable-next-line: await-in-sync
    async.schedule()
  end

  vim.list_extend(
    ret,
    HunkPreview.prepare_linespec_for_hunk(
      bufnr,
      preview.hunk,
      preview.removed,
      preview.added,
      preview.hunk.added
    )
  )
  return ret
end

--- @async
--- @param result Gitsigns.BlameInfoPublic
--- @param repo Gitsigns.Repo
--- @param with_gh boolean
--- @return Gitsigns.LineSpec
local function create_blame_title_linespec(result, repo, with_gh)
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

  return title
end

--- @async
--- @param bufnr integer
--- @param result Gitsigns.BlameInfoPublic
--- @param repo Gitsigns.Repo
--- @return Gitsigns.LineSpec[]
local function build_full_blame_body(bufnr, result, repo)
  local ret = {
    create_commit_msg_body_linespec(repo, result.sha),
  } --- @type Gitsigns.LineSpec[]

  vim.list_extend(ret, create_blame_hunk_linespec(bufnr, repo, result))
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
  if not is_committed(result) then
    if is_stale() then
      return
    end
    popup.create({ { { result.author, 'Label' } } }, config.preview_config, 'blame')
    return
  end

  local repo = bcache.git_obj.repo
  local body = opts.full and build_full_blame_body(bufnr, result, repo)
    or { { { result.summary, 'NormalFloat' } } }
  local blame_linespec = { create_blame_title_linespec(result, repo, false) }
  vim.list_extend(blame_linespec, body)

  if is_stale() then
    return
  end

  popup_winid, popup_bufnr = popup.create(blame_linespec, config.preview_config, 'blame')

  if not config.gh then
    return
  end

  blame_linespec = { create_blame_title_linespec(result, repo, true) }
  vim.list_extend(blame_linespec, body)

  if is_stale() then
    return
  end

  if api.nvim_win_is_valid(popup_winid) and api.nvim_buf_is_valid(popup_bufnr) then
    popup.update(popup_winid, popup_bufnr, blame_linespec, config.preview_config)
  end
end
