
local network = dofile "network.lua"

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
	self._gateway:send(self._index.."$"..data)
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
			c:setReceiver(function(s)
				local _, _, head, args = string.find(s, "^$(.)(.+)")
				head = tonumber(head)
				args = loadstring(args)()
				if head == 0 then -- new
					local client = network._connection.new(false)
					client._gateway = c
					client._index = args[1]
					client._ip = args[2]
					client._port = args[3]
					client.send = _proxy_send
					client.getpeername = _proxy_getpeername
					client.getsockname = _proxy_getsockname
					c.clients[args[1]] = client
					client.clients = false
					cb(client)
				elseif head == 1 then -- closed
					local c = c.clients[args[1]]
					if c.onClosed then
						c:onClosed()
					end
					c.clients[args[1]] = nil
				elseif head == 2 then -- message
					local client = c.clients[args[1]]
					local s = args[2]
					if client._receivable then
						network.dispatch(client, s)
					end
				end
			end)
		else
			c.clients = false
		end
		cb(c)
	end)
end

local function _gateway_receive_from_client(self, c, s)
	self:send("$2"..serialize{c._index, s})
end

local function _gateway_receive_from_server(self, s)
	local _, _, index, body = string.find(s, "(.+)$(.+)")
	index = tonumber(index)
	local c = self.clients[index]
	c:send(body)
end

local function _gateway_listen(self, ip, port, cb)
	return network.listen(ip, port, function(c)
		c._index = #self.clients + 1
		self.clients[c._index] = c
		self:send("$0"..serialize{c._index, c:getpeername()})
		c:setReceiver(function(s) _gateway_receive_from_client(self, c, s) end)
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
		c:setReceiver(function (s) _gateway_receive_from_server(c, s) end)
	end
	if cb then
		cb(c, e)
	end
	return c, e
end

return proxy
