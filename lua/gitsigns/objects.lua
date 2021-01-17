local v = require("gitsigns/validation")

local M = {}
M.validate = {}

local enabled = false

local function traceback(level)
  level = level or 1
  while true do
  local info = debug.getinfo(level, "Sl")
  if not info then
  break
  end
  if info.what == "C" then  -- is a C function?
  print(level, "C function")
  else  -- a Lua function
  print(("[%s]:%d"):format(info.short_src, info.currentline))
  end
  level = level + 1
  end
end

local function validate_schema(obj, schema)
  if enabled then
  local valid, err = schema(obj)
  if not valid then
  traceback(4)
  print(vim.inspect(err))
  end
  -- assert(valid, vim.inspect(err))
  end
end

local hunk_schema = v.is_table {
  type = v.in_list {"add", "change", "delete"},
  head = v.is_string(),
  lines = v.is_array(v.is_string()),
  start = v.is_number(),
  dend = v.is_number(),
  added = v.is_table {
  start = v.is_number(),
  count = v.is_number()
  },
  removed = v.is_table {
  start = v.is_number(),
  count = v.is_number()
  },
}

function M.validate.hunk(obj)
  validate_schema(obj, hunk_schema)
end

function M.validate.hunks(obj)
  validate_schema(obj, v.is_array(hunk_schema))
end

local signs_schema = v.is_array(v.is_table {
  type = v.in_list{"add", "change", "delete", "topdelete", "changedelete"},
  lnum = v.is_number(),
  count = v.optional(v.is_number())
})

function M.validate.signs(obj)
  validate_schema(obj, signs_schema)
end

local cache_entry_schema = v.is_table {
  file  = v.is_string(),  -- Full filename
  relpath  = v.is_string(), -- Relative path to toplevel
  object_name = v.optional(v.is_string()), -- Object name of file in index
  mode_bits   = v.optional(v.is_string()),
  toplevel    = v.is_string(),  -- Top level git directory
  gitdir      = v.is_string(),  -- Path to git directory
  staged      = v.is_string(),  -- Path to staged contents
  abbrev_head = v.is_string(),
  hunks = v.is_array(hunk_schema), -- List of hunk objects
  staged_diffs  = v.is_array(hunk_schema), -- List of staged hunks
  index_watcher = v.is_userdata() -- Timer object watching the files index
}

function M.validate.cache_entry(obj)
  validate_schema(obj, cache_entry_schema)
end

function M.validate.cache_entry_opt(obj)
  validate_schema(obj, v.optional(cache_entry_schema))
end

function M.validate.cache(obj)
  validate_schema(obj, v.is_array(cache_entry_schema))
end

function M.init(en)
  enabled = en
end

return M
