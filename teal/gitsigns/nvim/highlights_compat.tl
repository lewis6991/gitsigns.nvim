local M = {}

local type hlval = string|boolean|integer

local function parse_expr(x: hlval): string
  if not x then
    return 'NONE'
  end

  if x is integer then
    return ('#%06x'):format(x)
  else
    return tostring(x)
  end
end

local function parse_attrs(x: {string:hlval}): string
  local r: {string} = {}

  for k, a in pairs(x) do
    if a is boolean and a then
      r[#r+1] = k
    end
  end

  if #r > 0 then
    return table.concat(r, ',')
  end
  return 'NONE'
end

function M.highlight(group: string, opts: {string:hlval})
  local default = opts.default and 'default' or ''
  if opts.link then
    vim.cmd(table.concat({
      'highlight',
      default,
      'link',
      group,
      opts.link as string
    }, ' '))
  end

  local hi_args = {'highlight', default, group}

  for k, val in pairs{
    guifg   = parse_expr(opts.fg),
    guibg   = parse_expr(opts.bg),
    guisp   = parse_expr(opts.sp),
    gui     = parse_attrs(opts),
    ctermfg = 'NONE',
    ctermbg = 'NONE',
    cterm   = 'NONE',
  } do
    table.insert(hi_args, k..'='..val)
  end
  vim.cmd(table.concat(hi_args, ' '))
end

return M
