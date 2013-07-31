
local network = require "network"
local profiler = require "ProFi"
local span = 0.0001
local log = print
local print = function() end
local run = true
local spend

network._status.receiver = function()
	if not spend then
		spend = os.clock()
		-- profiler:start()
	elseif network._status.receives > 10000 and not record then
		log("spend", network._status.receives, os.clock() - spend)
		-- profiler:stop()
		-- profiler:report("sp-"..os.time()..".txt")
		record = true
	end
end
-- server
local cmd = {
	hello = function(...)
		print("hello", ...)
	end,
	hi = function(...)
		print("hi", ...)
		return "hi.ack"
	end,
	start = function()
	end,
	stop = function()
		log("stop", os.clock() - time)
	end,
	sub = {a = print, b = print},
}

local s
network.listen("127.0.0.1",10033, function(c)
	print("accept", c.clients) 
	s = s or c
	if c.clients then
		return
	end
	c:addPrivilege("cmd", cmd)
	c:setReceiver(function(s) print("receive", s[1], s[2]) end)
end)
-- network.addGateway(10003)
local fps = 0
local time = os.clock()
local maxm = 0
while run do
	fps = fps + 1
	network.step(span)
	if os.clock() - time > 1 then
		local m = (collectgarbage("count")/1024)
		maxm = m > maxm and m or maxm
		minf = minf or fps
		minf = fps < minf and fps or minf
		local a, b, c, rb, wb = 0, 0, 0, 0, 0
		if s then a, b, c, rb, wb = s._socket:getstats() end
		os.execute("title server fps = "..fps.."/"..minf..
			" r/w = "..network._status.receives.."/"..network._status.sends..
			" m = "..m.."/"..maxm..
			" rb/wb = "..rb.."/"..wb)
		network._status.receives = 0
		network._status.sends = 0
		time = os.clock()
		fps = 0
	end
end
