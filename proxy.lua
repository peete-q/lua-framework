
local network = require "network"

local proxy = {
	step = network.step,
	connect = network.connect,
	_status = network._status,
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

function proxy.isGateway(port)
	return _gateways[port]
end

local function _proxy_send(self, head, body)
	self._gateway:_send(">", {self._index, {head, body}})
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
		if proxy.isGateway(port) then
			c.clients = {}
			c:setReceiver(function(data)
				local head = data[1]
				local body = data[2]
				local index = body[1]
				if head == "+" then -- new
					local client = network._connection.new(false)
					client._gateway = c
					client._index = index
					client._ip = body[2]
					client._port = body[3]
					client._send = _proxy_send
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
				elseif head == "<" then -- message
					local client = c.clients[index]
					if client._receivable then
						if type(body[2]) ~= "table" then
							require"std"
							print(data)
						end
						table.insert(body[2], data[3])
						client._dispatch(client, body[2])
					end
				end
			end)
		end
		cb(c)
	end)
end

return proxy