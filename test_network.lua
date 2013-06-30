dofile 'network.lua'

-- server
local cmd = {
	hello = function(...)
		print('hello', ...)
	end,
	hi = function(...)
		print('hi', ...)
		return 'hi_ack'
	end,
	sub = {a = print, b=print},
}
network.listen('127.0.0.1',10001, function(c)
	print('accept', c) 
	con = c
	con:setReceivable(true)
	con:addPrivilege('cmd',cmd)
	con:setReceiver(function(s) print('receive', s) end)
end)

-- client
network.connect('127.0.0.1',10001, function(c)
	c:setReceivable(true)
	network.step(1)
	local h = c.cmd.hi(1,2,3)
	h.onAck = function(...) print('ack', ...) end
	c.cmd.hello(1,2,3)
	c.cmd.sub.a('sub.a')
	c:send'xxxxxxx'
	for i = 1, 10 do
		network.step(1)
	end
end)
