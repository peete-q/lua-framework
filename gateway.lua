
local network = require "network"

local _dorpc = network._dorpc
local _doack = network._doack
local _tryack = network._tryack

local gateway = {}

local function _gateway_upward(client, data)
	return client._gateway:_send("<", {client._index, data})
end

local function _gateway_downward(self, data)
	if data[1] ~= ">" then
		print("unknown message")
	elseif not _tryack(self, data[2][2]) then
		local body = data[2]
		local index = body[1]
		local c = self.clients[index]
		c:_send(body[2][1], body[2][2])
	end
end

local function _gateway_dispatch(connection, data)
	if not _doack(connection, data) then
		local ok, ack, ret, field, args = _dorpc(connection, data)
		if ok == "noprivilege" then
			if connection._noprivilege then
				connection._noprivilege(connection, data)
			end
		elseif ok == "ok" then
			if type(ret[1]) == "function" then
				ret[1](connection, {"@", {field,{unpack(ret, 2)}}})
			elseif ack and connection._respond then
				connection._respond(connection, ack, ret)
			end
		elseif ok == "error" then
			print("RPC error when call:"..table.concat(field, "."), ret)
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
					return _gateway_upward(c, {"@", {field,{...}}})
				end
			})
			return rpc
		end
		self.clients[c._index] = c
		self:_send("+", {c._index, c:getpeername()})
		c:setReceiver(function(data) _gateway_upward(c, data) end)
		if cb then
			cb(c)
		end
	end)
end

function gateway.launchGateway(ip, port, cb)
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

gateway.upward = _gateway_upward

return gateway