local binary = require "binary"
local socket = require "socket"
local encode = binary.pack
local decode = binary.unpack
local enhead = binary.tostring
local dehead = binary.tonumber

local function _newset()
    local reverse = {}
    local set = {}
    return setmetatable(set, {__index = {
        insert = function(set, value)
			assert(value)
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
local _listener = {
	__type = "network.listener",
}
function _listener.close(self, mode)
	if self._socket then
		_readings:remove(self._socket)
		_listenings[self._socket] = nil
		self._socket:shutdown(mode or "both")
		self._socket:close()
		self._socket = false
	end
end
local _waitings = {
	index = 0
}
local _connection = {
	__type = "network.connection",
}
local network = {
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
	local field = {}
	setmetatable(rpc, {
		__index = function(rpc, key)
			table.insert(field, key)
			return rpc
		end,
		__call = function(rpc, ...)
			return self:_send("@", {field, {...}})
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
	return self:_send("!", data)
end
function _connection._send(self, head, body)
	if not self._cache.outgoing then
		_writings:insert(self._socket)
		self._cache.outgoing = {
			data = {
				head,
				body,
			}
		}
		self._cache.last = self._cache.outgoing
	else
		self._cache.last.next = {
			data = {
				head,
				body,
			}
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
function _connection._noprivilege(self, data)
	print("RPC error, noprivilege", data)
end
function _connection.new(s)
	local self = {
		_socket = s,
		_privilege = {},
		_cache = {},
		_field = {},
		_receiver = false,
		_receivable = true,
		_dispatch = network.dispatch,
		_respond = network.respond,
	}
	setmetatable(self, _connection)
	if s then
		s:settimeout(0)
		s:setoption("tcp-nodelay", true)
		s:setoption("keepalive", true)
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
local function _dorpc(c, data)
	if data[1] == "@" then
		local body = data[2]
		local field = body[1]
		local args = body[2]
		local ack = data[3]
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
			return "noprivilege"
		end
		local ret = {pcall(rpc, unpack(args))}
		if not ret[1] then
			return "error", ack, ret[2], field, args
		end
		return "ok", ack, {unpack(ret, 2)}, field, args
	end
end
local function _doack(c, data)
	if data[1] == "#" then
		local body = data[2]
		local ack = body[1]
		_waitings[ack](unpack(body[2]))
		_waitings[ack] = nil
		return true
	end
end
local function _tryack(c, data)
	if data[1] == "#" then
		local body = data[2]
		local ack = body[1]
		if _waitings[ack] then
			_waitings[ack](unpack(body[2]))
			_waitings[ack] = nil
			return true
		end
	end
end
local _status = {
	sends = 0,
	receives = 0,
	sent = 0,
	received = 0,
	receiver = nil,
	sender = nil,
}
local function _recvraw(c, v)
	if not c._cache.need then
		local n, e = v:receive(4)
		if not n then
			if e == "closed" then
				return
			end
			print("receive head failed:"..e)
			return
		end
		c._cache.need = dehead(n)
	end
	local s, e, read = v:receive(c._cache.need)
	if not s then
		if e == "timeout" then
			c._cache.inpending = (c._cache.inpending or "")..read
			c._cache.need = c._cache.need - #read
			return
		end
		if e == "closed" then
			return
		end
		print("receive body failed:"..e)
		return
	end
	
	if #s < c._cache.need then
		c._cache.inpending = s
		c._cache.need = c._cache.need - #s
		return
	end
	c._cache.need = nil
	
	if c._cache.inpending then
		s = c._cache.inpending..s
		c._cache.inpending = nil
	end
	
	if c._receivable then
		c._dispatch(c, decode(s))
	end
	
	_status.receives = _status.receives + 1
	_status.received = _status.received + 4 + #s
	if _status.receiver then
		_status.receiver(_status.receives, _status.received)
	end
end
local function _recvpack(c, v)
	local t, e, size = v:receive()
	if not t then
		if e == "timeout" then
			return
		end
		if e == "closed" then
			return
		end
		print("receive body failed:"..e)
		return
	end
	
	if c._receivable then
		c._dispatch(c, t)
	end
	
	_status.receives = _status.receives + 1
	_status.received = _status.received + size
	if _status.receiver then
		_status.receiver(_status.receives, _status.received)
	end
end
local function _sendraw(c, v)
	if not c._cache.outpending then
		if c._cache.outgoing.onAck then
			_waitings.index = _waitings.index + 1
			table.insert(_waitings, _waitings.index, c._cache.outgoing.onAck)
			table.insert(c._cache.outgoing.data, _waitings.index)
		end
		local data = encode(c._cache.outgoing.data)
		c._cache.outpending = enhead(#data)..data
	end
	local ok, e, wrote = v:send(c._cache.outpending, c._cache.wrote)
	if not ok then
		if e == "timeout" then
			c._cache.wrote = wrote + 1
			return
		end
		if e == "closed" then
			return
		end
		print("send failed:"..e)
		return
	end
	c._cache.outpending = nil
	c._cache.wrote = nil
	
	_status.sends = _status.sends + 1
	_status.sent = _status.sent + ok
	if _status.sender then
		_status.sender()
	end
	return true
end
local function _sendpack(c, v)
	if not c._cache.outpending then
		if c._cache.outgoing.onAck then
			_waitings.index = _waitings.index + 1
			table.insert(_waitings, _waitings.index, c._cache.outgoing.onAck)
			table.insert(c._cache.outgoing.data, _waitings.index)
		end
		c._cache.outpending = c._cache.outgoing.data
	end
	local ok, e, wrote = v:send(c._cache.outpending)
	if not ok then
		if e == "timeout" then
			return
		end
		if e == "closed" then
			return
		end
		print("send failed:"..e)
		return
	end
	c._cache.outpending = nil
	
	_status.sends = _status.sends + 1
	_status.sent = _status.sent + ok
	if _status.sender then
		_status.sender()
	end
	return true
end

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
		repeat
			local listener = _listenings[v]
			if listener then
				local s, e = v:accept()
				if not s then
					if e == "closed" then
						break
					end
					print("accept failed:"..e)
					break
				end
				listener.incoming(_connection.new(s))
			else
				local c = _connectings[v]
				network._receive(c, v)
			end
		until true
	end
	for k, v in ipairs(writable) do
		local c = _connectings[v]
		while c._cache.outgoing do
			if not network._send(c, v) then
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
	if not _doack(connection, data) then
		local ok, ack, ret, field, args = _dorpc(connection, data)
		if ok == "noprivilege" then
			if connection._noprivilege then
				connection._noprivilege(connection, data)
			end
		elseif ok == "ok" then
			if ack and connection._respond then
				connection._respond(connection, ack, ret)
			end
		elseif ok == "error" then
			print("RPC error when call:"..table.concat(field, "."), ret)
		elseif connection._receiver then
			connection._receiver(data)
		end
	end
end
function network.respond(connection, ack, ret)
	connection:_send("#",{ack, ret})
end

network._connection = _connection
network._dorpc = _dorpc
network._doack = _doack
network._tryack = _tryack
network._status = _status
network._receive = _recvpack
network._send = _sendpack

return network