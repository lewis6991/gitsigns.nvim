--- @class vim.mpack.session
--- @field receive function

--- @class vim.mpack.Packer

--- @class vim.mpack.Unacker

--- @class vim.mpack
--- @field encode fun(obj: any): string
--- @field decode fun(obj: string): any
--- @field Packer fun(opts): vim.mpack.Packer
--- @field Session fun(opts): vim.mpack.session
--- @field Unpacker fun(opts): vim.mpack.Unacker
--- @field NIL userdata vim.NIL
local mpack = vim.mpack

-- temporary hack to be able to manipulate buffer/window/tabpage
local Buffer = {}
Buffer.__index = Buffer
function Buffer.new(id)
  return setmetatable({ id = id }, Buffer)
end

local Window = {}
Window.__index = Window
function Window.new(id)
  return setmetatable({ id = id }, Window)
end

local Tabpage = {}
Tabpage.__index = Tabpage
function Tabpage.new(id)
  return setmetatable({ id = id }, Tabpage)
end

local Response = {}
Response.__index = Response

function Response.new(msgpack_rpc_stream, request_id)
  return setmetatable({
    _msgpack_rpc_stream = msgpack_rpc_stream,
    _request_id = request_id,
  }, Response)
end

function Response:send(value, is_error)
  --- @type string[]
  local data = { self._msgpack_rpc_stream._session:reply(self._request_id) }
  if is_error then
    data[#data + 1] = self._msgpack_rpc_stream._pack(value)
    data[#data + 1] = self._msgpack_rpc_stream._pack(mpack.NIL)
  else
    data[#data + 1] = self._msgpack_rpc_stream._pack(mpack.NIL)
    data[#data + 1] = self._msgpack_rpc_stream._pack(value)
  end
  self._msgpack_rpc_stream._stream:write(table.concat(data))
end

--- @class MsgpackRpcStream
--- @field _stream ProcessStream
--- @field _session unknown
--- @field _pack unknown
local MsgpackRpcStream = {}
MsgpackRpcStream.__index = MsgpackRpcStream

--- @param stream ProcessStream
--- @return MsgpackRpcStream
function MsgpackRpcStream.new(stream)
  return setmetatable({
    _stream = stream,
    _pack = mpack.Packer({
      ext = {
        [Buffer] = function(o)
          return 0, mpack.encode(o.id)
        end,
        [Window] = function(o)
          return 1, mpack.encode(o.id)
        end,
        [Tabpage] = function(o)
          return 2, mpack.encode(o.id)
        end,
      },
    }),
    _session = mpack.Session({
      unpack = mpack.Unpacker({
        ext = {
          [0] = function(_c, s)
            return Buffer.new(mpack.decode(s))
          end,
          [1] = function(_c, s)
            return Window.new(mpack.decode(s))
          end,
          [2] = function(_c, s)
            return Tabpage.new(mpack.decode(s))
          end,
        },
      }),
    }),
  }, MsgpackRpcStream)
end

function MsgpackRpcStream:write(method, args, response_cb)
  local data --- @type string[]
  if response_cb then
    assert(type(response_cb) == 'function')
    data = { self._session:request(response_cb) }
  else
    data = { self._session:notify() }
  end

  data[#data + 1] = self._pack(method)
  data[#data + 1] = self._pack(args)

  self._stream:write(table.concat(data))
end

function MsgpackRpcStream:read_start(request_cb, notification_cb, eof_cb)
  self._stream:read_start(function(data)
    if not data then
      return eof_cb()
    end

    local type --- @type 'request'|'notification'|'response'
    local id_or_cb --- @type integer|function
    local method_or_error --- @type string?
    local args_or_result --- @type any
    local pos = 1
    local len = #data

    while pos <= len do
      type, id_or_cb, method_or_error, args_or_result, pos = self._session:receive(data, pos)
      if type == 'request' or type == 'notification' then
        if type == 'request' then
          request_cb(method_or_error, args_or_result, Response.new(self, id_or_cb))
        else
          notification_cb(method_or_error, args_or_result)
        end
      elseif type == 'response' then
        if method_or_error == mpack.NIL then
          method_or_error = nil
        else
          args_or_result = nil
        end
        id_or_cb(method_or_error, args_or_result)
      end
    end
  end)
end

function MsgpackRpcStream:read_stop()
  self._stream:read_stop()
end

function MsgpackRpcStream:close(signal)
  self._stream:close(signal)
end

return MsgpackRpcStream
