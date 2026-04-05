local M = {}

local function is_char(x)
  return x:match('[^=\'"%s]') ~= nil
end

local function enter_value_state(x, idx)
  local next_ch = x:sub(idx + 1, idx + 1)
  if next_ch == "'" or next_ch == '"' then
    return 'in_quote', next_ch, true
  end
  return 'in_value', '', false
end

--- @param named_args table<string, string|boolean|(string|boolean)[]>
--- @param name string
--- @param value string|boolean
local function set_named_arg(named_args, name, value)
  local existing = named_args[name]
  if existing == nil then
    named_args[name] = value
    return
  end

  if type(existing) == 'table' then
    existing[#existing + 1] = value
    return
  end

  named_args[name] = { existing, value }
end

--- @param argv string[]
--- @return string[], table<string, string|boolean|(string|boolean)[]>
function M.parse_argv(argv)
  local pos_args = {} --- @type string[]
  local named_args = {} --- @type table<string, string|boolean|(string|boolean)[]>

  for _, arg in ipairs(argv) do
    local offset = vim.startswith(arg, '--') and 3 or 1
    local eq = arg:find('=', offset, true)

    if eq ~= nil then
      set_named_arg(named_args, arg:sub(offset, eq - 1), arg:sub(eq + 1))
    elseif offset == 3 then
      set_named_arg(named_args, arg:sub(offset), true)
    else
      pos_args[#pos_args + 1] = arg
    end
  end

  return pos_args, named_args
end

-- Return positional arguments and named arguments
--- @param x string
--- @return string[], table<string, string|boolean|(string|boolean)[]>
function M.parse_args(x)
  --- @type string[], table<string, string|boolean|(string|boolean)[]>
  local pos_args, named_args = {}, {}

  local state = 'in_arg'
  local cur_arg = ''
  local cur_val = ''
  local cur_quote = ''

  local function peek(idx)
    return x:sub(idx + 1, idx + 1)
  end

  local i = 1
  while i <= #x do
    local ch = x:sub(i, i)
    -- dprintf('L(%d)(%s): cur_arg="%s" ch="%s"', i, state, cur_arg, ch)

    if state == 'in_arg' then
      if is_char(ch) then
        if ch == '-' and peek(i) == '-' then
          state = 'in_flag'
          cur_arg = ''
          i = i + 1
        else
          cur_arg = cur_arg .. ch
        end
      elseif ch:match('%s') then
        pos_args[#pos_args + 1] = cur_arg
        state = 'in_ws'
      elseif ch == '=' then
        cur_val = ''
        local skip_quote
        state, cur_quote, skip_quote = enter_value_state(x, i)
        if skip_quote then
          i = i + 1
        end
      end
    elseif state == 'in_flag' then
      if ch:match('%s') then
        set_named_arg(named_args, cur_arg, true)
        state = 'in_ws'
      elseif ch == '=' then
        cur_val = ''
        local skip_quote
        state, cur_quote, skip_quote = enter_value_state(x, i)
        if skip_quote then
          i = i + 1
        end
      else
        cur_arg = cur_arg .. ch
      end
    elseif state == 'in_ws' then
      if is_char(ch) then
        if ch == '-' and peek(i) == '-' then
          state = 'in_flag'
          cur_arg = ''
          i = i + 1
        else
          state = 'in_arg'
          cur_arg = ch
        end
      end
    elseif state == 'in_value' then
      if not ch:match('%s') then
        cur_val = cur_val .. ch
      elseif ch:match('%s') then
        set_named_arg(named_args, cur_arg, cur_val)
        cur_arg = ''
        state = 'in_ws'
      end
    elseif state == 'in_quote' then
      local next_ch = peek(i)
      if ch == '\\' and next_ch == cur_quote then
        cur_val = cur_val .. next_ch
        i = i + 1
      elseif ch == cur_quote then
        set_named_arg(named_args, cur_arg, cur_val)
        state = 'in_ws'
        if next_ch ~= '' and not next_ch:match('%s') then
          error('malformed argument: ' .. next_ch)
        end
      else
        cur_val = cur_val .. ch
      end
    end
    i = i + 1
  end

  if #cur_arg > 0 then
    if state == 'in_arg' then
      pos_args[#pos_args + 1] = cur_arg
    elseif state == 'in_flag' then
      set_named_arg(named_args, cur_arg, true)
    elseif state == 'in_value' then
      set_named_arg(named_args, cur_arg, cur_val)
    end
  end

  return pos_args, named_args
end

return M
