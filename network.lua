require "serialize"
local socket = require "socket"
local function _newset()
    local reverse = {}
    local set = {}
    return setmetatable(set, {__index = {
        insert = function(set, value)
            if not reverse[value] then
                table.insert(set, value)
                reverse[value] = table.getn(set)
            end
        end,
        remove = function(set, value)
            local index = reverse[value]
            if index then
                reverse[value] = nil
                local top = table.remove(set)
                if top ~= value then
                    reverse[top] = index
                    set[index] = top
                end
            end
        end
    }})
end
local _readings = _newset()
local _writings = _newset()
local _listenings = {}
local _connectings = {}
local _listener = {}
function _listener.close(self, mode)
	if self._socket then
		_readings:remove(self._socket)
		_listenings[self._socket] = nil
		self._socket:shutdown(mode or "both")
		self._socket:close()
		self._socket = false
	end
end
local _waitingAcks = {}
local _connection = {
	__type = "network.connection",
}
function _connection.__index(self, key)
	local m = _connection[key]
	if m then
		return m
	end
	local f = self._field[key]
	if f then
		return f()
	end
	local rpc = {}
	local buffer = {}
	setmetatable(rpc, {
		__index = function(rpc, key)
			table.insert(buffer, key)
			return rpc
		end,
		__call = function(rpc, ...)
			return self:send{buffer,{...}}
		end
	})
	return rpc[key]
end
function _connection.addPrivilege(self, key, privilege)
	self._privilege[key] = privilege
end
function _connection.removePrivilege(self, key)
	self._privilege[key] = nil
end
function _connection.clearPrivilege(self)
	self._privilege = {}
end
function _connection.setReceiver(self, cb)
	self._receiver = cb
end
function _connection.send(self, data)
	if not self._cache.outgoing then
		_writings:insert(self._socket)
		self._cache.outgoing = {
			data = data,
		}
		self._cache.last = self._cache.outgoing
	else
		self._cache.last.next = {
			data = data,
		}
		self._cache.last = self._cache.last.next
	end
	return self._cache.last
end
function _connection.close(self, mode)
	if self._socket then
		_readings:remove(self._socket)
		_connectings[self._socket] = nil
		self._socket:shutdown(mode or "both")
		self._socket:close()
		self._socket = false
	end
end
function _connection.setReceivable(self, on)
	self._receivable = on
end
function _connection.new(s)
	local self = {
		_socket = s,
		_privilege = {},
		_cache = {},
		_field = {},
		_receiver = false,
		_receivable = true,
		_noprivilege = false,
	}
	setmetatable(self, _connection)
	if s then
		s:settimeout(0)
		_readings:insert(s)
		_connectings[s] = self
	end
	return self
end
-- socket interface
function _connection.getpeername(self)
	return self._socket:getpeername()
end
function _connection.getsockname(self)
	return self._socket:getsockname()
end

local function _rpc_name(field)
	local name = field[1]
	for i = 2, #field do
		name = name.."."..field[i]
	end
	return name
end
local function _do_rpc(c, data)
	local _, _, message = data:find("^@(.+)")
	if message then
		local body = loadstring(message)()
		local field = body[1]
		local args = body[2]
		local ack = body[3]
		local rpc = c._privilege
		for i, v in ipairs(field) do
			if type(rpc) ~= "table" then
				break
			end
			rpc = rpc[v]
			if not rpc then
				break
			end
		end
		if type(rpc) ~= "function" then
			if c._noprivilege then
				c._noprivilege(c, data)
			else
				print("RPC error: no privilege ".._rpc_name(field))
			end
			return
		end
		local ret = {rpc(unpack(args))}
		if ack then
			c:send("#"..serialize{ack, ret})
		end
		return true
	end
end
local function _do_ack(c, data)
	local _, _, message = data:find("^#(.+)")
	if message then
		local body = loadstring(message)()
		local ack = body[1]
		_waitingAcks[ack](unpack(body[2]))
		_waitingAcks[ack] = nil
		return true
	end
end

network = {
	_connection = _connection,
}
function network.listen(ip, port, cb)
	local s = assert(socket.bind(ip, port))
	local self = {
		_socket = s,
		close = _listener.close,
	}
	_readings:insert(s)
	_listenings[s] = {
		ip = ip,
		port = port,
		incoming = cb,
	}
	s:settimeout(0)
	return self
end
function network.connect(ip, port, cb)
	local s, e = socket.connect(ip, port)
	local c = s and _connection.new(s)
	if cb then
		cb(c, e)
	end
	return c, e
end
function network.step(timeout)
	local readable, writable = socket.select(_readings, _writings, timeout)
	for k, v in ipairs(readable) do
		local listener = _listenings[v]
		if listener then
			local s = v:accept()
			listener.incoming(_connection.new(s))
		else
			local s = v:receive()
			local c = _connectings[v]
			if c._receivable then
				network.dispatch(c, s)
			end
		end
	end
	for k, v in ipairs(writable) do
		local c = _connectings[v]
		while c._cache.outgoing do
			if c._cache.outgoing.onAck then
				table.insert(_waitingAcks, c._cache.outgoing.onAck)
				table.insert(c._cache.outgoing.data, #_waitingAcks)
			end
			if type(c._cache.outgoing.data) == "table" then
				c._cache.outgoing.data = "@"..serialize(c._cache.outgoing.data)
			end
			local ok, e = v:send(c._cache.outgoing.data.."\n")
			if not ok then
				print("send failed:"..e)
				break
			end
			c._cache.outgoing = c._cache.outgoing.next
		end
		if not c._cache.outgoing then
			_writings:remove(v)
		end
	end
end
function network.dispatch(connection, data)
	if not _do_ack(connection, data) then
		if not next(connection._privilege) or not _do_rpc(connection, data) then
			if connection._receiver then
				connection._receiver(data)
			end
		end
	end
end

return network
