local M = {}

local function parse_expr(x)
   if not x then
      return 'NONE'
   end

   if math.type(x) == "integer" then
      return ('#%06x'):format(x)
   else
      return tostring(x)
   end
end

local function parse_attrs(x)
   local r = {}

   for k, a in pairs(x) do
      if type(a) == "boolean" and a then
         r[#r + 1] = k
      end
   end

   if #r > 0 then
      return table.concat(r, ',')
   end
   return 'NONE'
end

function M.highlight(group, opts)
   local default = opts.default and 'default' or ''
   if opts.link then
      vim.cmd(table.concat({
         'highlight',
         default,
         'link',
         group,
         opts.link,
      }, ' '))
   end

   local hi_args = { 'highlight', default, group }

   for k, val in pairs({
         guifg = parse_expr(opts.fg),
         guibg = parse_expr(opts.bg),
         guisp = parse_expr(opts.sp),
         gui = parse_attrs(opts),
         ctermfg = 'NONE',
         ctermbg = 'NONE',
         cterm = 'NONE',
      }) do
      table.insert(hi_args, k .. '=' .. val)
   end
   vim.cmd(table.concat(hi_args, ' '))
end

return M
