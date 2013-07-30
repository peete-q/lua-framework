local network = require "network"

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
network.listen("127.0.0.1",10001, function(c)
	print("accept", c) 
	c:addPrivilege("cmd",cmd)
	c:setReceiver(function(s) print("receive", unpack(s)) end)
end)

-- client
network.connect("127.0.0.1",10001, function(c, e)
	if not c then
		print("connect failed", e)
		return
	end
	network.step(1)
	local h = c.cmd.hi("say hi")
	h.onAck = function(...) print("ack", ...) end
	c.cmd.hello("say hi")
	c.cmd.sub.a("sub.a")
	c:send("xxxxxxx")
	for i = 1, 10 do
		network.step(1)
	end
end)
