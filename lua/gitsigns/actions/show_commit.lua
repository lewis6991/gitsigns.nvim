local Async = require('gitsigns.async')
local cache = require('gitsigns.cache').cache
local Util = require('gitsigns.util')
local Hunks = require('gitsigns.hunks')
local config = require('gitsigns.config').config

local api = vim.api

--- Find the hunk and file paths containing a line in a commit's patch.
--- @param lnum integer
--- @return Gitsigns.Hunk.Hunk
--- @return string
--- @return string
local function get_hunk(lnum)
  local new_file --- @type string?
  local old_file --- @type string?
  local hunk_line --- @type string?
  while true do
    local line = assert(api.nvim_buf_get_lines(0, lnum - 1, lnum, false)[1])

    new_file = line:match('^%+%+%+ b/(.*)') or new_file
    old_file = line:match('^%-%-%- a/(.*)') or old_file
    hunk_line = line:match('^@@ [^ ]+ [^ ]+ @@.*') or hunk_line
    if hunk_line and old_file and new_file then
      break
    end

    lnum = lnum - 1
  end
  assert(hunk_line and old_file and new_file, 'Failed to find hunk header or file names')

  return Hunks.parse_diff_line(hunk_line), old_file, new_file
end

local M = {}

--- Create or reuse a commit buffer without choosing a window.
--- Pass cached metadata and message lines to omit the patch and use gitcommit.
--- @async
--- @param repo Gitsigns.Repo
--- @param base string
--- @param message? string[]
--- @return integer commit_buf
function M.create_buf(repo, base, message)
  local lines = message or require('gitsigns.git.commit')(repo, base, 'full')
  -- Message and full commit views must not reuse each other's contents or mappings.
  local buffer_name = ('gitsigns%s://%s//%s'):format(message and '-commit' or '', repo.gitdir, base)
  if Util.bufexists(buffer_name) then
    return vim.fn.bufnr(buffer_name)
  end

  local commit_buf = api.nvim_create_buf(true, true)
  api.nvim_buf_set_name(commit_buf, buffer_name)
  api.nvim_buf_set_lines(commit_buf, 0, -1, false, lines)
  vim.bo[commit_buf].modifiable = false
  vim.bo[commit_buf].buftype = 'nofile'
  vim.bo[commit_buf].filetype = message and 'gitcommit' or 'git'
  vim.bo[commit_buf].bufhidden = 'wipe'
  if message then
    vim.keymap.set('n', 'q', '<cmd>close<CR>', {
      buffer = commit_buf,
      silent = true,
      desc = 'Close commit message',
    })
  end
  return commit_buf
end

--- Follow a parent or tree reference, or open a file at the selected patch line.
--- @param bufnr integer
--- @param commit_buf integer
--- @param ref_list string[]
--- @param ref_list_ptr integer
local function goto_action(bufnr, commit_buf, ref_list, ref_list_ptr)
  local curline = api.nvim_get_current_line()
  local header, ref = curline:match('^([a-z]+) (%x+)')
  if (header == 'tree' or header == 'parent') and ref then
    local ref_stack_ptr1 = ref_list_ptr + 1
    ref_list[ref_stack_ptr1] = ref
    for i = ref_stack_ptr1 + 1, #ref_list do
      ref_list[i] = nil
    end
    Async.run(M.show_commit, ref, 'edit', bufnr, ref_list, ref_stack_ptr1):raise_on_error()
    return
  elseif curline:match('^[%+%-]') then
    local lnum = api.nvim_win_get_cursor(0)[1]
    local hunk, old_file, new_file = get_hunk(lnum)
    local line = assert(api.nvim_buf_get_lines(commit_buf, lnum - 1, lnum, false)[1])
    local added = line:match('^%+')

    local commit =
      assert(assert(api.nvim_buf_get_lines(commit_buf, 0, 1, false)[1]):match('^commit (%x+)$'))

    if not added then
      commit = commit .. '^'
    end

    Async.run(function()
      require('gitsigns.actions.diffthis').show(bufnr, commit, added and new_file or old_file)
      api.nvim_win_set_cursor(0, { added and hunk.added.start or hunk.removed.start, 0 })
    end):raise_on_error()
  end
end

--- Open a full commit and install optional history and patch navigation mappings.
--- @async
--- @param base? string?
--- @param open? 'vsplit'|'tabnew'|'edit'
--- @param bufnr? integer
--- @param ref_list? string[]
--- @param ref_list_ptr? integer
--- @return integer? commit_buf
function M.show_commit(base, open, bufnr, ref_list, ref_list_ptr)
  base = Util.norm_base(base or 'HEAD') or 'HEAD'
  open = open or 'vsplit'
  bufnr = bufnr or api.nvim_get_current_buf()
  ref_list = ref_list or {}
  if #ref_list == 0 then
    ref_list[1] = base
    ref_list_ptr = 1
  else
    ref_list_ptr = ref_list_ptr or #ref_list
  end
  local bcache = cache[bufnr]
  if not bcache then
    return
  end

  local commit_buf = M.create_buf(bcache.git_obj.repo, base)
  vim.cmd[open]({ mods = { keepalt = true } })
  api.nvim_win_set_buf(0, commit_buf)

  if config._commit_maps then
    vim.keymap.set('n', '<CR>', function()
      goto_action(bufnr, commit_buf, ref_list, ref_list_ptr)
    end, { buffer = commit_buf, silent = true })

    vim.keymap.set('n', '<C-o>', function()
      local prev_ptr = ref_list_ptr - 1
      local ref = ref_list[prev_ptr]
      if ref then
        Async.run(M.show_commit, ref, 'edit', bufnr, ref_list, prev_ptr):raise_on_error()
      end
    end, { buffer = commit_buf, silent = true })

    vim.keymap.set('n', '<C-i>', function()
      local next_ptr = ref_list_ptr + 1
      local ref = ref_list[next_ptr]
      if ref then
        Async.run(M.show_commit, ref, 'edit', bufnr, ref_list, next_ptr):raise_on_error()
      end
    end, { buffer = commit_buf, silent = true })
  end

  return commit_buf
end

return M
