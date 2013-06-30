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
local _listener = {}
local _waitingAcks = {}
local _connection = {
	__type = "network.connection",
}
function _connection.__index(self, key)
	local m = _connection[key]
	if m then
		return m
	end
	local rpc = {}
	local buffer = {}
	setmetatable(rpc, {
		__index = function(rpc, key)
			table.insert(buffer, key)
			return rpc
		end,
		__call = function(rpc, ...)
			return self:send(serialize(buffer).."@"..serialize{...}.."@")
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
	self.incoming = cb
end
function _connection.send(self, data)
	if not self._field.outgoing then
		_writings:insert(self.socket)
		self._field.outgoing = {
			data = data,
		}
		self._field.last = self._field.outgoing
	else
		self._field.last.next = {
			data = data,
		}
		self._field.last = self._field.last.next
	end
	return self._field.last
end
function _connection.close(self)
end
function _connection.setReceivable(self, on)
	if on then
		_readings:insert(self.socket)
	else
		_readings:remove()
	end
end
function _connection.new(s)
	local self = {
		socket = s,
		_privilege = {},
		_field = {},
		_cache = {},
	}
	setmetatable(self, _connection)
	s:settimeout(0)
	_connection[s] = self
	return self
end
local function _rpc_name(filed)
	local name = filed[1]
	for i = 2, #filed do
		name = name.."."..filed[i]
	end
	return name
end
local function _do_rpc(c, data)
	local _, _, filed, args, ack = data:find("(.+)@(.+)@(.*)")
	if filed then
		filed = loadstring(filed)()
		args = loadstring(args)()
		local rpc = c._privilege
		for i, v in ipairs(filed) do
			if type(rpc) ~= "table" then
				break
			end
			rpc = rpc[v]
			if not rpc then
				break
			end
		end
		if type(rpc) ~= "function" then
			print("RPC error: no _privilege ".._rpc_name(filed))
			return
		end
		
		local ret = {rpc(unpack(args))}
		if ack ~= "" then
			c:send(ack.."#"..serialize(ret))
		end
		return true
	end
end
local function _do_ack(c, data)
	local _, _, ack, param = data:find("(.+)#(.+)")
	if ack then
		ack = tonumber(ack)
		_waitingAcks[ack](unpack(loadstring(param)()))
		_waitingAcks[ack] = nil
		return true
	end
end

network = {}
function network.listen(ip, port, cb)
	local s = assert(socket.bind(ip, port))
	local listener = {
		socket = s,
		close = _listener.close,
	}
	_readings:insert(s)
	_listenings[s] = {
		ip = ip,
		port = port,
		incoming = cb,
	}
	s:settimeout(0)
	return listener
end
function network.connect(ip, port, cb)
	local s, e = socket.connect(ip, port)
	if s then
		cb(_connection.new(s))
	else
		cb(nil, e)
	end
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
			local c = _connection[v]
			if not _do_ack(c, s) then
				if #c._privilege > 0 or not _do_rpc(c, s) then
					c.incoming(s)
				end
			end
		end
	end
	for k, v in ipairs(writable) do
		local c = _connection[v]
		while c._field.outgoing do
			if c._field.outgoing.onAck then
				table.insert(_waitingAcks, c._field.outgoing.onAck)
				c._field.outgoing.data = c._field.outgoing.data..#_waitingAcks
			end
			local ok, e = v:send(c._field.outgoing.data.."\n")
			if not ok then
				print("send failed:"..e)
				break
			end
			c._field.outgoing = c._field.outgoing.next
		end
		if not c._field.outgoing then
			_writings:remove(v)
		end
	end
end

