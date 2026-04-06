local orig_pcall = pcall

if package.loaded['jit'] then
  local coxpcall = orig_pcall(require, 'coxpcall')
  if coxpcall then
    pcall = coxpcall.pcall
  end
end

local helpers = require('nvim-test.helpers')
local gs_helpers = require('test.gs_helpers')

return function(busted, _helper, options)
  helpers.options = options
  gs_helpers.pending = busted.pending

  busted.subscribe({ 'suite', 'start' }, function()
    gs_helpers.cleanup_scratch_root()
  end)

  busted.subscribe({ 'suite', 'end' }, function()
    gs_helpers.cleanup_scratch_root()
  end)

  return true
end
