local argparse = require('gitsigns.cli.argparse')

--- @class Gitsigns.CliLineContext
--- @field completing_subcmd boolean
--- @field subcmd string?
--- @field pos_args string[]

local M = {}
local COMMAND = 'Gitsigns'

--- @param args string[]
--- @param trailing_space boolean
--- @return string?
--- @return string[]
local function parse_prev_args(args, trailing_space)
  local last = trailing_space and #args or (#args - 1)
  if last < 2 then
    return args[1], {}
  end

  local pos_args = argparse.parse_argv(vim.list_slice(args, 2, last))
  return args[1], pos_args
end

--- Parse a command-line string up to the cursor for completion.
--- Uses the same argument parser as command execution for preceding args.
--- @param line string
--- @return Gitsigns.CliLineContext
function M.parse(line)
  local trailing_space = line:match('%s$') ~= nil
  local ok, parsed = pcall(vim.api.nvim_parse_cmd, line, {})

  if ok and parsed.cmd == COMMAND then
    local args = parsed.args or {}
    local completing_subcmd = #args == 0 or (#args == 1 and not trailing_space)
    local subcmd, pos_args = parse_prev_args(args, trailing_space)

    return {
      completing_subcmd = completing_subcmd,
      subcmd = subcmd,
      pos_args = completing_subcmd and {} or pos_args,
    }
  end

  local words = vim.split(line, '%s+', { trimempty = false })
  local cmd_idx = 1

  for i, word in ipairs(words) do
    if word ~= '' and vim.startswith(COMMAND, word) then
      cmd_idx = i
      break
    end
  end

  local args = vim.list_slice(words, cmd_idx + 1, #words)
  if trailing_space and args[#args] == '' then
    table.remove(args, #args)
  end

  local completing_subcmd = #args == 0 or (#args == 1 and not trailing_space)
  local subcmd, pos_args = parse_prev_args(args, trailing_space)

  return {
    completing_subcmd = completing_subcmd,
    subcmd = subcmd,
    pos_args = completing_subcmd and {} or pos_args,
  }
end

return M
