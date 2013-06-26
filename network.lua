
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
local _connection = {}
local _waitingAcks = {}
function _connection.addPrivilege(self, key, privilege)
  self.privilege[key] = privilege
end
function _connection.removePrivilege(self, key)
	self.privilege[key] = nil
end
function _connection.clearPrivilege(self)
	self.privilege = {}
end
function _connection.setReceiver(self, cb)
	self.incoming = cb
end
function _connection.send(self, data)
	if not self.outgoing then
		_writings:insert(self.socket)
		self.outgoing = {
			data = data,
		}
		self.last = self.outgoing
	else
		self.last.next = {
			data = data,
		}
		self.last = self.last.next
	end
	return self.last
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
		__type = "network.communicator",
		socket = s,
		addPrivilege = _connection.addPrivilege,
		removePrivilege = _connection.removePrivilege,
		clearPrivilege = _connection.clearPrivilege,
		setReceiver = _connection.setReceiver,
		setReceivable = _connection.setReceivable,
		send = _connection.send,
		close = _connection.close,
		rpc = {},
		privilege = {},
	}
	local field = {}
	setmetatable(self.rpc, {
		__index = function(rpc, name)
			table.insert(field, name)
			return rpc
		end,
		__call = function(rpc, ...)
			local h = self:send(serialize(field).."@"..serialize{...}.."@")
			field = {}
			return h
		end
	})
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
		local rpc = c.privilege
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
			print("RPC error: no privilege ".._rpc_name(filed))
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

network = {
}
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
	local s = assert(socket.connect(ip, port))
	return _connection.new(s)
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
				if #c.privilege > 0 or not _do_rpc(c, s) then
					c.incoming(s)
				end
			end
		end
	end
	for k, v in ipairs(writable) do
		local c = _connection[v]
		while c.outgoing do
			if c.outgoing.onAck then
				table.insert(_waitingAcks, c.outgoing.onAck)
				c.outgoing.data = c.outgoing.data..#_waitingAcks
			end
			local ok, e = v:send(c.outgoing.data.."\n")
			if not ok then
				print("send failed:"..e)
				break
			end
			c.outgoing = c.outgoing.next
		end
		if not c.outgoing then
			_writings:remove(v)
		end
	end
end

