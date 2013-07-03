local network = dofile "proxy.lua"

-- server
local cmd = {
  hello = function(...)
		print("hello", ...)
	end,
	hi = function(...)
		print("hi", ...)
		return "hi_ack"
	end,
	sub = {a = print, b = print},
}
network.listen("127.0.0.1",10003, function(c)
	print("accept", c.clients) 
	if c.clients then
		return
	end
	c:addPrivilege("cmd", cmd)
	c:setReceiver(function(s) print("receive", s) end)
end)
network.addGateway(10003)

-- gateway
local gateway = network.launchGateway("127.0.0.1",10003)
gateway:listen("127.0.0.1",10004, function(c) print("new client", c._socket) end)
network.step(1)

-- client
network.connect("127.0.0.1",10004, function(c, e)
	if not c then
		print("connect failed", e)
		return
	end
	network.step(1)
	local h = c.cmd.hi(1,2,3)
	h.onAck = function(...) print("ack", ...) end
	c.cmd.hello(1,2,3)
	c.cmd.sub.a("sub.a")
	c:send"xxxxxxx"
	for i = 1, 10 do
		network.step(1)
	end
end)
