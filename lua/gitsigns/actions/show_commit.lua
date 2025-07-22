local async = require('gitsigns.async')
local cache = require('gitsigns.cache').cache
local util = require('gitsigns.util')

local api = vim.api

--- @param base? string?
--- @param open? 'vsplit'|'tabnew'
--- @async
return function(base, open)
  base = util.norm_base(base or 'HEAD')
  open = open or 'vsplit'
  local bufnr = api.nvim_get_current_buf()
  local bcache = cache[bufnr]
  if not bcache then
    return
  end

  local res = bcache.git_obj.repo:command({ 'show', base })
  async.schedule()
  local buffer_name = bcache:get_rev_bufname(base, false)
  local commit_buf = nil
  -- find preexisting commit buffer or create a new one
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_get_name(buf) == buffer_name then
      commit_buf = buf
      break
    end
  end
  if commit_buf == nil then
    commit_buf = api.nvim_create_buf(true, true)
    api.nvim_buf_set_name(commit_buf, buffer_name)
    api.nvim_buf_set_lines(commit_buf, 0, -1, false, res)
    vim.bo[commit_buf].modifiable = false
    vim.bo[commit_buf].buftype = 'nofile'
    vim.bo[commit_buf].filetype = 'git'
    vim.bo[commit_buf].bufhidden = 'wipe'
  end
  vim.cmd[open]({ mods = { keepalt = true } })
  api.nvim_win_set_buf(0, commit_buf)
end
