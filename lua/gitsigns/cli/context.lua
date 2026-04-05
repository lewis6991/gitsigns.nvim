local argparse = require('gitsigns.cli.argparse')

--- @class Gitsigns.CliLineContext
--- @field words string[]
--- @field subcmd_idx integer
--- @field subcmd string?
--- @field pos_args string[]

local M = {}

--- Parse a command-line string up to the cursor for completion.
--- Uses the same argument parser as command execution for preceding args.
--- @param line string
--- @return Gitsigns.CliLineContext
function M.parse(line)
  local words = vim.split(line, '%s+', { trimempty = false })
  local cmd_idx = 1

  for i, word in ipairs(words) do
    if word == 'Gitsigns' then
      cmd_idx = i
      break
    end
  end

  local subcmd_idx = cmd_idx + 1
  local prev_words = vim.list_slice(words, subcmd_idx + 1, #words - 1)
  local pos_args = argparse.parse_args(table.concat(prev_words, ' '))

  return {
    words = words,
    subcmd_idx = subcmd_idx,
    subcmd = words[subcmd_idx],
    pos_args = pos_args,
  }
end

return M
