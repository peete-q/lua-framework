local network = dofile "proxy.lua"

-- server
local cmd = {
	hello = function(...)
		print("hello", ...)
	end,
	hi = function(...)
		print("hi", ...)
		return "hi.ack"
	end,
	sub = {a = print, b = print},
}
network.listen("127.0.0.1",10003, function(c)
	print("accept") 
	if c._clients then
		return
	end
	c:addPrivilege("cmd", cmd)
	c:setReceiver(function(s, ...) print("server receive", s, ...) end)
end)
network.addGateway(10003)

-- gateway
local gateway = network.launchGateway("127.0.0.1",10003)
gateway:listen("127.0.0.1",10004, function(c) 
	print("new client", c._socket)
	-- c.remote.cmd.hi("g2c hi")
	-- c:send("xxxxxxx")
end)
network.step(1)

-- client
network.connect("127.0.0.1",10004, function(c, e)
	if not c then
		print("connect failed", e)
		return
	end
	c:addPrivilege("cmd", cmd)
	c:setReceiver(function(s, ...) print("client receive", s, ...) end)
	network.step(1)
	print('cccccccc', c._socket:getwriter():size())
	-- local h = c.remote.cmd.hi("say hi")
	-- h.onAck = function(...) print("ack", ...) end
	c.remote.cmd.hello("say hello")
	-- c.remote.cmd.sub.a("sub.a")
	-- c:send("xxxxxxx")
	for i = 1, 10 do
		network.step(1)
	end
end)
