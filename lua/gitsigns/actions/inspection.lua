--- Helpers for inspection-style tabs and panels.
---
--- Blame and history can temporarily move the user into revision buffers with
--- attached panels. This module keeps the shared window selection rules in one
--- place: which windows count as panels, which buffers can act as targets, and
--- how panel state moves when a revision is opened in a new tab.
local cache = require('gitsigns.cache').cache

local api = vim.api

local M = {}

local panel_filetypes = {
  ['gitsigns-blame'] = true,
  ['gitsigns-history'] = true,
}

--- @param tabpage integer?
--- @return integer[]
local function list_wins(tabpage)
  if tabpage and tabpage ~= 0 and not api.nvim_tabpage_is_valid(tabpage) then
    return {}
  end
  return api.nvim_tabpage_list_wins(tabpage or 0)
end

--- @param win integer
--- @return boolean
function M.is_panel_win(win)
  if not api.nvim_win_is_valid(win) then
    return false
  end

  local bufnr = api.nvim_win_get_buf(win)
  return panel_filetypes[vim.bo[bufnr].filetype] == true
end

--- @param bufnr integer
--- @return boolean
function M.is_revision_buf(bufnr)
  return vim.startswith(api.nvim_buf_get_name(bufnr), 'gitsigns://')
end

--- @param tabpage integer?
--- @param win integer
--- @return boolean
local function win_is_in_tab(tabpage, win)
  for _, tab_win in ipairs(list_wins(tabpage)) do
    if tab_win == win then
      return true
    end
  end
  return false
end

--- @param win integer
--- @return boolean
local function is_target_candidate_win(win)
  return api.nvim_win_is_valid(win) and not M.is_panel_win(win)
end

--- @param win integer
--- @return boolean
local function is_target_win(win)
  return is_target_candidate_win(win) and cache[api.nvim_win_get_buf(win)] ~= nil
end

--- @param tabpage? integer
--- @param preferred? integer
--- @return integer?
function M.find_target_win(tabpage, preferred)
  if preferred and win_is_in_tab(tabpage, preferred) and is_target_win(preferred) then
    return preferred
  end

  local current = api.nvim_get_current_win()
  if win_is_in_tab(tabpage, current) and is_target_win(current) then
    return current
  end

  for _, win in ipairs(list_wins(tabpage)) do
    if is_target_win(win) then
      return win
    end
  end
end

--- @param tabpage? integer
--- @param win integer?
--- @return boolean
function M.has_target_candidate_win(tabpage, win)
  return win ~= nil and win_is_in_tab(tabpage, win) and is_target_candidate_win(win)
end

--- @param tabpage? integer
--- @param filetype string
--- @return integer?
function M.find_panel_win(tabpage, filetype)
  for _, win in ipairs(list_wins(tabpage)) do
    local bufnr = api.nvim_win_get_buf(win)
    if vim.bo[bufnr].filetype == filetype then
      return win
    end
  end
end

--- @param win integer
--- @return integer source_win
--- @return integer bufnr
--- @return Gitsigns.CacheEntry? bcache
function M.get_source_context(win)
  local bufnr = api.nvim_win_get_buf(win)
  local bcache = cache[bufnr]
  if not bcache and M.is_panel_win(win) then
    local target_win = M.find_target_win(0, win)
    if target_win then
      win = target_win
      api.nvim_set_current_win(win)
      bufnr = api.nvim_win_get_buf(win)
      bcache = cache[bufnr]
    end
  end

  return win, bufnr, bcache
end

--- @async
--- @param bufnr integer
--- @param revision string?
--- @param relpath string?
--- @return boolean did_attach
function M.show_revision_in_new_tab(bufnr, revision, relpath)
  local old_tabpage = api.nvim_get_current_tabpage()
  vim.cmd.tabnew({ mods = { keepalt = true } })

  local did_attach = require('gitsigns.actions.diffthis').show(bufnr, revision, relpath)
  if not did_attach then
    pcall(vim.cmd.tabclose)
    if api.nvim_tabpage_is_valid(old_tabpage) then
      pcall(api.nvim_set_current_tabpage, old_tabpage)
    end
    return false
  end

  return true
end

--- @param tabpage? integer
function M.close_panels(tabpage)
  tabpage = tabpage or api.nvim_get_current_tabpage()

  for _, win in ipairs(list_wins(tabpage)) do
    if M.is_panel_win(win) then
      pcall(api.nvim_win_close, win, true)
    end
  end
end

return M
