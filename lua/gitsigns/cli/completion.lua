local cmdline = require('gitsigns.cli.context')
local generated = require('gitsigns.cli.completion.generated')

--- @class Gitsigns.GeneratedCompletionPositional
--- @field name string
--- @field boolean? boolean
--- @field revision? boolean
--- @field required? boolean
--- @field values? string[]

--- @alias Gitsigns.GeneratedCompletionFlag false|true|string[]

--- @class Gitsigns.GeneratedCompletionAction
--- @field positional Gitsigns.GeneratedCompletionPositional[]?
--- @field flags table<string, Gitsigns.GeneratedCompletionFlag>?

local M = {}

--- @param arglead string
--- @param matches string[]
--- @return string[]
local function complete_matches(arglead, matches)
  return vim.tbl_filter(
    --- @param x string
    --- @return boolean
    function(x)
      return vim.startswith(x, arglead)
    end,
    matches
  )
end

--- @param ... string[]?
--- @return string[]
local function merge_completions(...)
  local ret = {} --- @type string[]
  local seen = {} --- @type table<string, boolean>

  for i = 1, select('#', ...) do
    for _, match in ipairs(select(i, ...) or {}) do
      if not seen[match] then
        seen[match] = true
        ret[#ret + 1] = match
      end
    end
  end

  return ret
end

--- @param arglead string
--- @return string[]
local function complete_heads(arglead)
  --- @type string[]
  local all =
    vim.fn.systemlist({ 'git', 'rev-parse', '--symbolic', '--branches', '--tags', '--remotes' })
  return complete_matches(arglead, all)
end

--- @param arglead string
--- @param values string[]?
--- @return string[]
local function complete_values(arglead, values)
  return complete_matches(arglead, values or {})
end

--- @param arglead string
--- @param spec Gitsigns.GeneratedCompletionPositional?
--- @return string[]
local function complete_positional(arglead, spec)
  if not spec then
    return {}
  end

  return merge_completions(
    spec.revision and complete_heads(arglead) or nil,
    complete_values(arglead, spec.values),
    spec.boolean and complete_values(arglead, { 'true', 'false' }) or nil,
    spec.required ~= true and complete_values(arglead, { 'nil' }) or nil
  )
end

--- @param arglead string
--- @param name string
--- @param spec Gitsigns.GeneratedCompletionFlag
--- @return string[]
local function complete_flag_value(arglead, name, spec)
  local prefix = '--' .. name

  if spec == false then
    return complete_matches(arglead, {
      prefix .. '=true',
      prefix .. '=false',
    })
  end

  if spec == true then
    return {}
  end

  local matches = {} --- @type string[]
  for _, value in ipairs(spec) do
    matches[#matches + 1] = prefix .. '=' .. value
  end

  return complete_matches(arglead, matches)
end

--- @param arglead string
--- @param name string
--- @param spec Gitsigns.GeneratedCompletionFlag
--- @return string[]
local function complete_flag(arglead, name, spec)
  local prefix = '--' .. name
  local eq = arglead:find('=', 1, true)

  if eq then
    if arglead:sub(1, eq - 1) ~= prefix then
      return {}
    end
    return complete_flag_value(arglead, name, spec)
  end

  if spec == false then
    return complete_matches(arglead, { prefix })
  end

  return complete_matches(arglead, { prefix .. '=' })
end

--- @param arglead string
--- @param flags table<string, Gitsigns.GeneratedCompletionFlag>?
--- @return string[]
local function complete_flags(arglead, flags)
  local matches = {} --- @type string[]
  local flag_specs = flags or {} --- @type table<string, Gitsigns.GeneratedCompletionFlag>
  local flag_names = vim.tbl_keys(flag_specs)
  table.sort(flag_names)

  for _, flag_name in ipairs(flag_names) do
    local flag_spec = flag_specs[flag_name] --- @type Gitsigns.GeneratedCompletionFlag
    vim.list_extend(matches, complete_flag(arglead, flag_name, flag_spec))
  end

  return matches
end

--- @param name string
--- @return (fun(arglead: string, line: string): string[])?
function M.for_action(name)
  local spec = generated.actions[name] --- @type Gitsigns.GeneratedCompletionAction?
  if not spec then
    return
  end

  local positional = spec.positional or {}
  local flags = spec.flags or {}

  return function(arglead, line)
    local ctx = cmdline.parse(line)

    if vim.startswith(arglead, '--') then
      return complete_flags(arglead, flags)
    end

    local next_pos = positional[#ctx.pos_args + 1]
    local matches = complete_positional(arglead, next_pos)

    if arglead == '' then
      return merge_completions(matches, complete_flags(arglead, flags))
    end

    return matches
  end
end

return M
