local helpers = require('test.gs_helpers')

local clear = helpers.clear
local eq = helpers.eq
local exec_lua = helpers.exec_lua
local setup_path = helpers.setup_path
local supports_source_hls = helpers.supports_source_hls

helpers.env()

describe('render capture', function()
  before_each(function()
    clear()
    setup_path()
  end)

  it('captures overlapping extmark highlights with priority order', function()
    local text, layers, stack = exec_lua(function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'abcdef' })
      local ns = vim.api.nvim_create_namespace('gitsigns_test_capture')

      vim.api.nvim_buf_set_extmark(0, ns, 0, 1, {
        end_col = 4,
        hl_group = 'DiffAdd',
        priority = 90,
      })
      vim.api.nvim_buf_set_extmark(0, ns, 0, 2, {
        end_col = 4,
        hl_group = 'Search',
        priority = 95,
      })
      vim.api.nvim_buf_set_extmark(0, ns, 0, 2, {
        end_col = 5,
        hl_group = 'Error',
        priority = 100,
      })

      local Capture = require('gitsigns.render.capture')
      local line = Capture.capture_line(0, 0)
      return line.text, line.layers, Capture.hl_stack_at(line, 2)
    end)

    eq('abcdef', text)

    if not supports_source_hls() then
      eq(0, #layers)
      eq({}, stack)
      return
    end

    eq(3, #layers)

    local add_priority
    local search_priority
    local error_priority
    for _, layer in ipairs(layers) do
      local hl = layer.hl_group
      if hl == 'Error' then
        error_priority = layer.priority
      elseif hl == 'DiffAdd' then
        add_priority = layer.priority
      elseif hl == 'Search' then
        search_priority = layer.priority
      end
    end

    assert(add_priority ~= nil)
    assert(search_priority ~= nil)
    assert(error_priority ~= nil)
    eq(true, add_priority <= search_priority)
    eq(true, search_priority <= error_priority)
    eq({ 'DiffAdd', 'Search', 'Error' }, stack)
  end)

  it('keeps hl_eol extmarks in the captured line stack', function()
    local layers, stack = exec_lua(function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'foo' })
      local ns = vim.api.nvim_create_namespace('gitsigns_test_capture_eol')
      vim.api.nvim_buf_set_extmark(0, ns, 0, 0, {
        hl_group = 'ErrorMsg',
        hl_eol = true,
      })

      local Capture = require('gitsigns.render.capture')
      local line = Capture.capture_line(0, 0)
      return line.layers, Capture.hl_stack_at(line, 2)
    end)

    if not supports_source_hls() then
      eq(0, #layers)
      eq({}, stack)
      return
    end

    eq(1, #layers)
    eq({ 'ErrorMsg' }, stack)
  end)

  it('applies full-line and word-diff overlays without rendering', function()
    local full_stack, diff_stack, plain_stack = exec_lua(function()
      local Capture = require('gitsigns.render.capture')
      local Overlay = require('gitsigns.render.overlay')

      local lines = {
        { text = 'abc', layers = {} },
      }

      Overlay.add_full_line_layer(lines, 'GitSignsDeleteVirtLn', 1000)
      Overlay.add_word_diff_layers(lines, { { 1, 'change', 2, 3 } }, function(region_type)
        return region_type == 'change' and 'GitSignsChangeInline' or nil
      end, 1001, { ensure_min_width = true })

      local line = lines[1]
      return Capture.hl_stack_at(line, 3),
        Capture.hl_stack_at(line, 1),
        Capture.hl_stack_at(line, 0)
    end)

    eq({ 'GitSignsDeleteVirtLn' }, full_stack)
    eq({ 'GitSignsDeleteVirtLn', 'GitSignsChangeInline' }, diff_stack)
    eq({ 'GitSignsDeleteVirtLn' }, plain_stack)
  end)
end)
