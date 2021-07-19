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
  buffer  = 'boolean',
  expr    = 'boolean',
  noremap = 'boolean',
  nowait  = 'boolean',
  script  = 'boolean',
  silent  = 'boolean',
  unique  = 'boolean',
}

local function validate_option_keywords(options: table)
  for option_name, expected_type in pairs(valid_options) do
    local value = options[option_name]
    if value then
      validate {
        [option_name] = { value, expected_type };
      }
    end
  end
end

local function apply_mappings(mappings: {string:any}, bufnr: integer)
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
      options = vim.tbl_extend('keep', default_options, options) as {string:any}

      validate_option_keywords(options)

      local mode, mapping = key:match("^(.)[ ]*(.+)$")

      if not mode or not valid_modes[mode] then
        error("Invalid mode specified for keymapping. mode="..mode)
      end

      -- In case users haven't updated their config.
      options.buffer = nil

      api.nvim_buf_set_keymap(bufnr, mode, mapping, rhs, options)
    until true
  end
end

return apply_mappings
