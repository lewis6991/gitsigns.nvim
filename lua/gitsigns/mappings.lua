


local validate = vim.validate
local api = vim.api

local valid_modes = {
   n = 'n', v = 'v', x = 'x', i = 'i', o = 'o', t = 't', c = 'c', s = 's',

   ['!'] = '!', [' '] = '',
}

local valid_options = {
   buffer = 'boolean',
   expr = 'boolean',
   noremap = 'boolean',
   nowait = 'boolean',
   script = 'boolean',
   silent = 'boolean',
   unique = 'boolean',
}

local function validate_option_keywords(options)
   for option_name, expected_type in pairs(valid_options) do
      local value = options[option_name]
      if value then
         validate({
            [option_name] = { value, expected_type },
         })
      end
   end
end

local function apply_mappings(mappings, bufnr)
   validate({
      mappings = { mappings, 'table' },
   })

   local default_options = {}
   for key, val in pairs(mappings) do

      if valid_options[key] then
         default_options[key] = val
      end
   end

   for key, opts in pairs(mappings) do
      repeat

         if valid_options[key] then
            break
         end

         local rhs
         local options
         if type(opts) == "string" then
            rhs = opts
            options = {}
         elseif type(opts) == "table" then
            rhs = opts[1]
            local boptions = {}
            for k in pairs(valid_options) do
               boptions[k] = opts[k]
            end
            options = boptions
         else
            error(("Invalid type for option rhs: %q = %s"):format(type(opts), vim.inspect(opts)))
         end
         options = vim.tbl_extend('keep', default_options, options)

         validate_option_keywords(options)

         local mode, mapping = key:match("^(.)[ ]*(.+)$")

         if not mode or not valid_modes[mode] then
            error("Invalid mode specified for keymapping. mode=" .. mode)
         end


         options.buffer = nil

         api.nvim_buf_set_keymap(bufnr, mode, mapping, rhs, options)
      until true
   end
end

return apply_mappings
