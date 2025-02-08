local helpers = require('test.gs_helpers')

local exec_lua = helpers.exec_lua
local eq = helpers.eq

helpers.env()

--- @param hunks [string,integer,integer,integer,integer][]
--- @return [string,integer,integer][]
local function calc_signs(hunks)
  for i, hunk in ipairs(hunks) do
    if hunk[1] then
      hunks[i] = {
        added = { count = hunk[4], start = hunk[5] },
        removed = { count = hunk[2], start = hunk[3] },
        type = hunk[1],
      }
    end
  end

  --- @type Gitsigns.Sign[]
  local signs = exec_lua(
    --- @param hunks0 Gitsigns.Hunk.Hunk[]
    --- @return Gitsigns.Sign[]
    function(hunks0)
      local Hunks = require('gitsigns.hunks')
      local signs = {}
      for i, hunk in ipairs(hunks0) do
        local prev_hunk, next_hunk = hunks0[i - 1], hunks0[i + 1]
        vim.list_extend(signs, Hunks.calc_signs(prev_hunk, hunk, next_hunk))
      end
      return signs
    end,
    hunks
  )

  local r = {} --- @type [string,integer,integer][]
  for i, s in ipairs(signs) do
    r[i] = { s.type, s.lnum, s.count }
  end
  return r
end

describe('hunksigns', function()
  before_each(function()
    exec_lua(function(path)
      package.path = path
      require('gitsigns').setup({ _new_sign_calc = true })
    end, package.path)
  end)

  it('calculate topdelete signs', function()
    eq({ { 'topdelete', 1, 1 } }, calc_signs({ { 'delete', 1, 1, 0, 0 } }))
  end)

  it('calculate topdelete signs with changedelete', function()
    eq(
      { { 'changedelete', 1, 1 } },
      calc_signs({
        { 'delete', 1, 1, 0, 0 },
        { 'change', 1, 2, 1, 1 },
      })
    )
  end)

  it('delete, change, topdelete', function()
    eq(
      {
        { 'delete', 1, 1 },
        { 'change', 2, 1 },
        { 'topdelete', 3, 1 },
      },
      calc_signs({
        { 'delete', 1, 2, 0, 1 },
        { 'change', 1, 3, 1, 2 },
        { 'delete', 1, 4, 0, 2 },
      })
    )
  end)

  it('delete, change, change, topdelete', function()
    eq(
      {
        { 'delete', 1, 1 },
        { 'change', 2, 2 },
        { 'change', 3 },
        { 'topdelete', 4, 1 },
      },
      calc_signs({
        { 'delete', 1, 2, 0, 1 },
        { 'change', 2, 3, 2, 2 },
        { 'delete', 1, 5, 0, 3 },
      })
    )
  end)

  it('delete, change, changedelete', function()
    local r = calc_signs({
      { 'delete', 1, 2, 0, 1 },
      { 'change', 1, 3, 1, 2 },
      { 'delete', 1, 4, 0, 2 },
      { 'change', 1, 5, 1, 3 },
    })

    -- TODO(lewis6991): not perfect. Better signs would be
    --   { 'delete', 1, 1 },
    --   { 'changedelete', 2, 1 },
    --   { 'change', 3, 1 },

    eq({
      { 'delete', 1, 1 },
      { 'change', 2, 1 },
      { 'delete', 2, 1 },
      { 'change', 3, 1 },
    }, r)
  end)
end)
