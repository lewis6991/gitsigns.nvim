global _: any

global _TEST: boolean

global loadstring: function(string): (function(): any)

global unpack: function<T>({T}, number, number): T...

global getfenv: function(function): table

global record jit
  arch: string
  os: string
  version: string
  version_num: number
  off: function()
  off: function(function)
  on: function()
  status: function(): boolean
end

global vim = require('vim')
