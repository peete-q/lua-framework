local network = require "network"
-- server
local cmd = {
  hello = function(...)
		print('hello', ...)
	end,
	hi = function(...)
		print('hi', ...)
		return 'hi'
	end,
	sub = {a = print, b=print},
}
network.listen('127.0.0.1',10001, function(c)
	print('accept', c) 
	con = c
	con:setReceivable(true)
	con:addPrivilege('cmd',cmd)
end)
-- client
local cl = network.connect('127.0.0.1',10001)
cl:setReceivable(true)
network.step(1)
con:setReceiver(function(s) print('receive', s) end)
local h = cl.cmd.hi(1,2,3)
h.onAck = function(...) print('ack', ...) end
cl.cmd.hello(1,2,3)
cl.cmd.sub.a('sub.a')
cl:send'xxxxxxx'
for i = 1, 10 do
	network.step(1)
end
