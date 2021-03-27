-- Originated from:
-- https://github.com/norcalli/neovim-plugin/blob/master/lua/neovim-plugin/apply_mappings.lua

local validate = vim.validate
local api = vim.api

local valid_modes: {string:string} = {
  n = 'n'; v = 'v'; x = 'x'; i = 'i'; o = 'o'; t = 't'; c = 'c'; s = 's';
  -- :map! and :map
  ['!'] = '!'; [' '] = '';
}

local valid_options: {string:string} = {
  expr    = 'boolean',
  noremap = 'boolean',
  nowait  = 'boolean',
  script  = 'boolean',
  silent  = 'boolean',
  unique  = 'boolean',
  buffer  = 'boolean',
}

local function validate_option_keywords(options: table)
  for option_name, expected_type in pairs(valid_options) do
    local value = options[option_name]
    if value then
      validate {
        [option_name] = { value, expected_type } as {any};
      }
    end
  end
end

local function apply_mappings(mappings: {string:any}, bufonly: boolean)
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
  for key, opts in pairs(mappings) do
    repeat
      -- Skip any inline default keywords.
      if valid_options[key] then
        break
      end

      local rhs: string
      local options: {string:any}
      if opts is string then
        rhs = opts
        options = {}
      elseif opts is table then
        rhs = opts[1] as string
        local boptions = {}
        for k in pairs(valid_options) do
          boptions[k] = opts[k]
        end
        options = boptions
      else
        error(("Invalid type for option rhs: %q = %s"):format(type(opts), vim.inspect(opts)))
      end
      options = vim.tbl_extend('keep', default_options, options as table) as {string:any}

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
