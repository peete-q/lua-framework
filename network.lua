local stream = require "stream"
local socket = require "socket"

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
	FLAG_UNKNOW	= 0,
	FLAG_RPC	= 1,
	FLAG_ACK	= 2,
	FLAG_CUSTOM	= 3,
}

_connection.__index = _connection
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
function _connection.send(self, ...)
	return self:_send(network.FLAG_UNKNOW, ...)
end
function _connection.setReceivable(self, on)
	self._receivable = on
end
function _connection.close(self, mode)
	if self._closed then
		return
	end
	self._closed = true
	
	if self._socket then
		_readings:remove(self._socket)
		_writings:remove(self._socket)
		_connectings[self._socket] = nil
		self._socket:shutdown(mode or "both")
		self._socket:close()
		self._socket = false
	end
	
	if self.onClosed then
		self:onClosed()
	end
end
-- private
function _connection._send(self, ...)
	assert(not self._closed, "connection closed")
	if not self._packet.first then
		_writings:insert(self._socket)
		self._packet.first = {
			data = {...},
		}
		self._packet.last = self._packet.first
	else
		self._packet.last.next = {
			data = {...},
		}
		self._packet.last = self._packet.last.next
	end
	return self._packet.last
end
function _connection._ready(self)
	_writings:insert(self._socket)
end
function _connection._noprivilege(self, rpc)
	print("RPC error: noprivilege '"..rpc.."'")
end
function _connection._respond(self, ack, ret)
	self:_send(network.FLAG_ACK, ack, ret)
end
function _connection._dorpc(self, reader, nb)
	local field, args, ack = reader:read(nb)
	local rpc = self._privilege
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
		if self._noprivilege then
			self:_noprivilege(table.concat(field, "."))
		end
		return
	end
	local ret = {pcall(rpc, unpack(args))}
	if ret[1] then
		if ack and self._respond then
			self:_respond(ack, {unpack(ret, 2)})
		end
		return
	end
	local info = table.concat(field, ".").."("..table.concat(args, ",")..")"
	print("RPC error when call:"..info..":"..ret[2])
end
function _connection._doack(self, reader, nb)
	local ack, ret = reader:read(nb)
	_waitings[ack](unpack(ret))
	_waitings[ack] = nil
end
function _connection._dispatch(self, reader, nb, tail)
	local flag = reader:read()
	local cb = self._dispatchers[flag]
	if cb then
		cb(self, reader, nb - 1, tail)
	elseif self._receiver then
		self._receiver(flag, reader:read(nb - 1))
	end
end
function _connection.new(s)
	local self = {
		_socket = s,
		_privilege = {},
		_packet = {},
		_receivable = true,
		_dispatch = network.dispatch,
		_respond = network.respond,
		_closed = nil,
		_clients = nil,
		_receiver = nil,
		onClosed = nil,
		remote = {},
	}
	self._dispatchers = {
		[network.FLAG_RPC] = _connection._dorpc,
		[network.FLAG_ACK] = _connection._doack,
	}
	setmetatable(self, _connection)
	
	local _remote_call = function(_, key)
		local rpc = {}
		local field = {key}
		setmetatable(rpc, {
			__index = function(rpc, key)
				table.insert(field, key)
				return rpc
			end,
			__call = function(rpc, ...)
				return self:_send(network.FLAG_RPC, field, {...})
			end
		})
		return rpc
	end
	setmetatable(self.remote, {__index = _remote_call, __newindex = _remote_call})
	if s then
		s:settimeout(0)
		s:setoption("tcp-nodelay", true)
		s:setoption("keepalive", true)
		s:setreader(stream.new())
		s:setwriter(stream.new())
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

local _stats = {
	requests = 0,
	handles = 0,
	sends = 0,
	receives = 0,
	overreceives = 0,
	oversends = 0,
	sent = 0,
	received = 0,
	receiver = nil,
	sender = nil,
}
function network._receive(c, v)
	local ok, e = v:receive()
	if not ok then
		if e == "timeout" then
			_stats.overreceives = _stats.overreceives + 1
			return
		end
		if e == "closed" then
			c:close()
			return
		end
		print("receive failed:"..e)
		return
	end
	_stats.receives = _stats.receives + 1
	_stats.received = _stats.received + ok
	if _stats.receiver then
		_stats.receiver(_stats.receives, _stats.received)
	end
	
	local reader = v:getreader()
	while true do
		if not c._packet.need then
			if reader:unread() < 4 then
				break
			end
			c._packet.need = reader:readf("D")
		end
		
		if reader:unread() < c._packet.need then
			break
		end
		
		local tail = reader:tell() + c._packet.need
		local nb = reader:readf("B")
		if c._receivable then
			c._dispatch(c, reader, nb, tail)
		else
			reader:read(nb)
		end
		c._packet.need = nil
		_stats.handles = _stats.handles + 1
	end
	reader:remove(0, reader:tell())
end
function network._send(c, v)
	local writer = v:getwriter()
	while c._packet.first do
		local this = c._packet.first
		if this.onAck then
			_waitings.index = _waitings.index + 1
			_waitings[_waitings.index] = this.onAck
			table.insert(this.data, _waitings.index)
		end
		local pos = writer:size()
		writer:writef("B", #this.data)
		writer:write(unpack(this.data))
		writer:insertf(pos, "D", writer:size() - pos)
		c._packet.first = this.next
		_stats.requests = _stats.requests + 1
	end
	
	if writer:size() > 0 then
		local ok, e = v:send()
		if not ok then
			if e == "timeout" then
				_stats.oversends = _stats.oversends + 1
				return
			end
			if e == "closed" then
				c:close()
				return
			end
			print("send failed:"..e)
			return
		end
		
		if writer:empty() then
			_writings:remove(v)
		end
		
		_stats.sends = _stats.sends + 1
		_stats.sent = _stats.sent + ok
		if _stats.sender then
			_stats.sender()
		end
	end
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
		if c then
			network._send(c, v)
		end
	end
end

network._connection = _connection
network._stats = _stats

return network