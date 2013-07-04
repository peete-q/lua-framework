
local network = dofile "network.lua"

local _do_rpc = network._do_rpc
local _do_ack = network._do_ack
local _rpc_name = network._rpc_name

local proxy = {
	step = network.step,
	connect = network.connect,
}

local _gateways = {}

function proxy.addGateway(port)
	if not _gateways[port] then
		_gateways[port] = {}
	end
end

function proxy.removeGateway(port)
	_gateways[port] = nil
end

function proxy.queryGateway(port)
	return _gateways[port]
end

local function _proxy_send(self, data)
	self._gateway:send("&"..self._index.."&"..data)
end

local function _proxy_getpeername(self)
	return self._ip, self._port
end

local function _proxy_getsockname(self)
	return self._gateway:_proxy_getsockname()
end

function proxy.listen(ip, port, cb)
	return network.listen(ip, port, function(c)
		local ip, port = c:getsockname()
		local tb = proxy.queryGateway(port)
		if tb then
			c.clients = {}
			c:setReceiver(function(data)
				local _, _, head, index, args = string.find(data, "^&(.)&(.+)&(.*)")
				index = tonumber(index)
				if head == "+" then -- new
					local client = network._connection.new(false)
					args = loadstring(args)()
					client._gateway = c
					client._index = index
					client._ip = args[1]
					client._port = args[2]
					client.send = _proxy_send
					client.getpeername = _proxy_getpeername
					client.getsockname = _proxy_getsockname
					c.clients[index] = client
					client.clients = false
					cb(client)
				elseif head == "-" then -- closed
					local c = c.clients[index]
					if c.onClosed then
						c:onClosed()
					end
					c.clients[index] = nil
				elseif head == "=" then -- message
					local client = c.clients[index]
					if client._receivable then
						client._dispatch(client, args)
					end
				end
			end)
		else
			c.clients = false
		end
		cb(c)
	end)
end

local function _gateway_upward(client, data)
	return client._gateway:send("&=&"..client._index.."&"..data)
end
proxy.upward = _gateway_upward

local function _gateway_downward(self, data)
	local _, _, index, body = string.find(data, "^&(.+)&(.+)")
	index = tonumber(index)
	local c = self.clients[index]
	c:send(body)
end

local function _gateway_dispatch(connection, data)
	if not _do_ack(connection, data) then
		local ok, ack, ret, field, args = _do_rpc(connection, data)
		if ok == "noprivilege" then
			if connection._noprivilege then
				connection._noprivilege(connection, data)
			end
		elseif ok == "ok" then
			if type(ret[1]) == "function" then
				ret[1](connection, "@"..serialize{field,{unpack(ret, 2)}}.."@")
			elseif ack and connection._respond then
				connection._respond(connection, ack, ret)
			end
		elseif ok == "error" then
			print("RPC error when call:".._rpc_name(field), ret)
		elseif connection._receiver then
			connection._receiver(data)
		end
	end
end

local function _gateway_listen(self, ip, port, cb)
	return network.listen(ip, port, function(c)
		c._index = #self.clients + 1
		c._gateway = self
		c._noprivilege = _gateway_upward
		c._dispatch = _gateway_dispatch
		c._field.upward = function ()
			local rpc = {}
			local field = {}
			setmetatable(rpc, {
				__index = function(rpc, key)
					table.insert(field, key)
					return rpc
				end,
				__call = function(rpc, ...)
					return _gateway_upward(c, "@"..serialize{field,{...}}.."@")
				end
			})
			return rpc
		end
		self.clients[c._index] = c
		self:send("&+&"..c._index.."&"..serialize{c:getpeername()})
		c:setReceiver(function(data) _gateway_upward(c, data) end)
		if cb then
			cb(c)
		end
	end)
end

function proxy.launchGateway(ip, port, cb)
	local c, e = network.connect(ip, port)
	if c then
		c.clients = {}
		c.listen = _gateway_listen
		c:setReceiver(function (data) _gateway_downward(c, data) end)
	end
	if cb then
		cb(c, e)
	end
	return c, e
end

return proxy
