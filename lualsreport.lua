#!/usr/bin/env -S nvim -l

--- @class LuaLS.Diagnostic.Range
--- @field end { character: integer, line: integer }
--- @field start { character: integer, line: integer }

--- @class LuaLS.Diagnostic
--- @field message string
--- @field code string
--- @field severity integer
--- @field source string
--- @field range LuaLS.Diagnostic.Range

local COLORS = {
  RED = '\27[31m',
  GREEN = '\27[32m',
  YELLOW = '\27[33m',
  BLUE = '\27[34m',
  MAGENTA = '\27[35m',
  GREY = '\27[90m',
  RESET = '\27[0m'
}

local SEV_COLORS = {
  [vim.diagnostic.severity.ERROR] = COLORS.RED,
  [vim.diagnostic.severity.WARN] = COLORS.YELLOW,
  [vim.diagnostic.severity.INFO] = COLORS.BLUE,
  [vim.diagnostic.severity.HINT] = COLORS.GREEN,
}

--- @type table<string,LuaLS.Diagnostic[]>
local report = vim.json.decode(io.stdin:read('*a'))

for f, diags in pairs(report) do
  local fpath = f:match('^file://(.+)$') or f

  -- Convert absolute path to relative path
  fpath = assert(vim.fn.fnamemodify(fpath, ':~:.'))

  local lines = {} --- @type string[]
  for line in io.lines(fpath) do
    table.insert(lines, line)
  end

  for _, diag in ipairs(diags) do
    local rstart = diag.range.start
    local rend = diag.range['end']
    io.write(
      ('%s%s:%s:%s%s [%s%s%s] %s %s(%s)%s\n'):format(
        COLORS.BLUE,
        fpath,
        rstart.line,
        rstart.character,
        COLORS.RESET,
        SEV_COLORS[diag.severity],
        vim.diagnostic.severity[diag.severity],
        COLORS.RESET,
        diag.message:gsub('\n', '; '),
        COLORS.MAGENTA,
        diag.code,
        COLORS.RESET
      )
    )
    io.write(lines[rstart.line + 1], '\n')
    io.write(COLORS.GREY)
    io.write((' '):rep(rstart.character), '^')
    if rstart.line == rend.line then
      io.write(('^'):rep(rend.character - rstart.character - 1))
    end
    io.write(COLORS.RESET, '\n')
  end
end

if next(report) then
  os.exit(1)
end
