-- Originated from:
-- https://github.com/norcalli/neovim-plugin/blob/master/lua/neovim-plugin/apply_mappings.lua

local validate = vim.validate
local api = vim.api

local valid_modes = {
  n = 'n'; v = 'v'; x = 'x'; i = 'i'; o = 'o'; t = 't'; c = 'c'; s = 's';
  -- :map! and :map
  ['!'] = '!'; [' '] = '';
}

local valid_options = {
  expr    = 'boolean',
  noremap = 'boolean',
  nowait  = 'boolean',
  script  = 'boolean',
  silent  = 'boolean',
  unique  = 'boolean',
  buffer  = 'boolean',
}

local function validate_option_keywords(options)
  validate { options = { options, 'table' } }
  for option_name, expected_type in pairs(valid_options) do
    local value = options[option_name]
    if value then
      validate {
        [option_name] = { value, expected_type };
      }
    end
  end
  return true
end

local function apply_mappings(mappings, bufonly)
  validate {
    mappings = { mappings, 'table' };
  }

  local default_options = {}
  for key, val in pairs(mappings) do
    -- Skip any inline default keywords.
    if valid_options[key] then
      default_options[key] = val
    end
  end

  -- May or may not be used.
  local current_bufnr = api.nvim_get_current_buf()
  for key, options in pairs(mappings) do
    repeat
      -- Skip any inline default keywords.
      if valid_options[key] then
        break
      end

      local rhs
      if type(options) == 'string' then
        rhs = options
        options = {}
      elseif type(options) == 'table' then
        rhs = options[1]
        local boptions = {}
        for k in pairs(valid_options) do
          boptions[k] = options[k]
        end
        options = boptions
      else
        error(("Invalid type for option rhs: %q = %s"):format(type(options), vim.inspect(options)))
      end
      options = vim.tbl_extend('keep', default_options, options)

      validate_option_keywords(options)

      if bufonly ~= options.buffer then
        break
      end

      local mode, mapping = key:match("^(.)[ ]*(.+)$")

      if not mode or not valid_modes[mode] then
        error("Invalid mode specified for keymapping. mode="..mode)
      end

      if options.buffer then
        options.buffer = nil
        api.nvim_buf_set_keymap(current_bufnr, mode, mapping, rhs, options)
      else
        api.nvim_set_keymap(mode, mapping, rhs, options)
      end
    until true
  end
end

return apply_mappings
