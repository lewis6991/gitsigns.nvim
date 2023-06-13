local M = {}

local function is_char(x)
  return x:match('[^=\'"%s]') ~= nil
end

-- Return positional arguments and named arguments
--- @param x string
function M.parse_args(x)
  --- @type string[], table<string,string|boolean>
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
        local next_ch = peek(i)
        if next_ch == "'" or next_ch == '"' then
          cur_quote = next_ch
          i = i + 1
          state = 'in_quote'
        else
          state = 'in_value'
        end
      end
    elseif state == 'in_flag' then
      if ch:match('%s') then
        named_args[cur_arg] = true
        state = 'in_ws'
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
      if is_char(ch) then
        cur_val = cur_val .. ch
      elseif ch:match('%s') then
        named_args[cur_arg] = cur_val
        cur_arg = ''
        state = 'in_ws'
      end
    elseif state == 'in_quote' then
      local next_ch = peek(i)
      if ch == '\\' and next_ch == cur_quote then
        cur_val = cur_val .. next_ch
        i = i + 1
      elseif ch == cur_quote then
        named_args[cur_arg] = cur_val
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
      named_args[cur_arg] = true
    elseif state == 'in_value' then
      named_args[cur_arg] = cur_val
    end
  end

  return pos_args, named_args
end

return M
