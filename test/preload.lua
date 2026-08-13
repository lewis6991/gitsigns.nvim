local orig_pcall = pcall

if package.loaded['jit'] then
  local ok, coxpcall = orig_pcall(require, 'coxpcall')
  if ok then
    pcall = coxpcall.pcall
  end
end

local helpers = require('nvim-test.helpers')
local gs_helpers = require('test.gs_helpers')

-- A test that wedges the editor produces no output at all: the runner blocks
-- in an RPC request that never returns, and CI kills the job minutes later
-- with the last completed test as the only clue. Trace each test in and out so
-- the log names the one that hung. Unbuffered, since nothing gets to flush.
local function trace(event, element)
  if os.getenv('GITSIGNS_TEST_TRACE') ~= '1' then
    return
  end
  io.stderr:write(
    ('[trace %.2f] %s %s\n'):format(os.clock(), event, (element and element.name) or '?')
  )
  io.stderr:flush()
end

return function(busted, _helper, options)
  helpers.options = options
  gs_helpers.pending = busted.pending

  busted.subscribe({ 'suite', 'start' }, function()
    gs_helpers.cleanup_scratch_root()
  end)

  busted.subscribe({ 'suite', 'end' }, function()
    gs_helpers.cleanup_scratch_root()
  end)

  busted.subscribe({ 'test', 'start' }, function(element)
    trace('test start', element)
  end)

  busted.subscribe({ 'test', 'end' }, function(element)
    trace('test end  ', element)
  end)

  return true
end
