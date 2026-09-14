local api = vim.api

--- @class Gitsigns.DiffBufferRef
--- @field refs integer
--- @field bufhidden ''|'hide'|'unload'|'delete'|'wipe'
--- @field loaded boolean
--- @field created boolean

-- Panels and standalone unified views can retain the same comparison buffer.
local refs = {} --- @type table<integer, Gitsigns.DiffBufferRef>
local M = {}

--- Keep a buffer loaded until the last view using it closes.
--- @param buf integer
--- @param created? boolean
--- @param loaded? boolean
function M.retain(buf, created, loaded)
  local ref = refs[buf]
  if not ref then
    ref = {
      refs = 0,
      bufhidden = vim.bo[buf].bufhidden,
      loaded = loaded or false,
      created = created or false,
    }
    refs[buf] = ref
  end
  ref.refs = ref.refs + 1
  vim.bo[buf].bufhidden = 'hide'
end

--- Restore the original buffer policy once no view retains it.
--- @param buf integer
--- @param keep? boolean The buffer is about to be reused by another layout.
function M.release(buf, keep)
  local ref = refs[buf]
  ref.refs = ref.refs - 1
  if ref.refs > 0 then
    return
  end
  refs[buf] = nil
  if not api.nvim_buf_is_valid(buf) then
    return
  end

  -- Preserve later user changes to buffer policy, text, or window placement.
  if vim.bo[buf].bufhidden == 'hide' then
    vim.bo[buf].bufhidden = ref.bufhidden
  end
  if not keep and not ref.loaded and not vim.bo[buf].modified and #vim.fn.win_findbuf(buf) == 0 then
    api.nvim_buf_delete(buf, { unload = not ref.created })
  end
end

return M
