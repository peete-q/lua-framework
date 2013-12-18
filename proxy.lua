
local network = require "network"

local proxy = {
	step = network.step,
	connect = network.connect,
	_stats = network._stats,
	
	FLAG_PROXY_ACCEPT	= network.FLAG_CUSTOM + 1,
	FLAG_PROXY_CLOSE	= network.FLAG_CUSTOM + 2,
	FLAG_PROXY_DOWNWARD	= network.FLAG_CUSTOM + 3,
	FLAG_PROXY_DISPATCH	= network.FLAG_CUSTOM + 4,
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

local function _proxy_send(self, ...)
	self._gateway:_send(proxy.FLAG_PROXY_DOWNWARD, self._index, ...)
end

local function _proxy_getpeername(self)
	return self._ip, self._port
end

local function _proxy_getsockname(self)
	return self._gateway:getsockname()
end

local function _proxy_close(self, reader, nb, tail)
	local index = reader:read()
	local c = self._clients[index]
	if c.onClosed then
		c:onClosed()
	end
	self._clients[index] = nil
end

local function _proxy_dispatch(self, reader, nb, tail)
	local index = reader:read()
	local c = self._clients[index]
	c:_dispatch(reader, nb - 1, tail)
end

function proxy.listen(ip, port, cb)
	return network.listen(ip, port, function(c)
		local ip, port = c:getsockname()
		if proxy.isGateway(port) then
			c._clients = {}
			c._dispatchers[proxy.FLAG_PROXY_ACCEPT] = function(self, reader, nb, tail)
				assert(nb == 3)
				local index, ip, port = reader:read(3)
				local c = network._connection.new(false)
				c._gateway = self
				c._index = index
				c._ip = ip
				c._port = port
				c._send = _proxy_send
				c.getpeername = _proxy_getpeername
				c.getsockname = _proxy_getsockname
				self._clients[c._index] = c
				cb(c)
			end
			c._dispatchers[proxy.FLAG_PROXY_CLOSE] = _proxy_close
			c._dispatchers[proxy.FLAG_PROXY_DISPATCH] = _proxy_dispatch
		end
		cb(c)
	end)
end

local function _gateway_upward_dispatch(self, reader, nb, tail)
	local writer = self._gateway._socket:getwriter()
	local pos = writer:size()
	writer:writef("Boo", nb + 2, proxy.FLAG_PROXY_DISPATCH, self._index)
	writer:extract(reader, tail - reader:tell())
	writer:insertf(pos, "D", writer:size() - pos)
	self._gateway:_ready()
	network._stats.writtens = network._stats.writtens + 1
end

local function _gateway_downward_dispatch(self, reader, nb, tail)
	local index = reader:read()
	local c = self._clients[index]
	if c then
		local writer = c._socket:getwriter()
		local pos = writer:size()
		writer:writef("B", nb - 1)
		writer:extract(reader, tail - reader:tell())
		writer:insertf(pos, "D", writer:size() - pos)
		c:_ready()
		network._stats.writtens = network._stats.writtens + 1
	end
end

local function _gateway_listen(self, ip, port, cb)
	return network.listen(ip, port, function(c)
		self._clients.n = self._clients.n + 1
		c._index = self._clients.n
		c._gateway = self
		c._dispatch = _gateway_upward_dispatch
		c.onClosed = function()
			self:_send(proxy.FLAG_PROXY_CLOSE, c._index)
			self._clients[c._index] = nil
		end
		self._clients[c._index] = c
		
		local writer = self._socket:getwriter()
		local p1, p2 = writer:writef("Boooo", 4, proxy.FLAG_PROXY_ACCEPT, c._index, c:getpeername())
		writer:insertf(p1, "D", p2 - p1)
		self:_ready()
		
		if cb then
			cb(c)
		end
	end)
end

function proxy.launchGateway(ip, port, cb)
	local c, e = network.connect(ip, port)
	if c then
		c.listen = _gateway_listen
		c._clients = {n = 0}
		c._dispatchers[proxy.FLAG_PROXY_DOWNWARD] = _gateway_downward_dispatch
	end
	if cb then
		cb(c, e)
	end
	return c, e
end

return proxy