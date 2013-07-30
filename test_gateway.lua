
local network = require "proxy"
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
		-- profiler:report("gp-"..os.time()..".txt")
		record = true
	end
end

-- gateway
local s
local gateway = network.launchGateway("127.0.0.1",10003)
for i = 10004, 10014 do
	gateway:listen("127.0.0.1", i, function(c) 
		print("new client", c._socket)
		local cmd = {
			hello = function(...)
				print("gateway hello",...)
				return network.upward, "gateway upward", ...
			end,
			hi = function(...)
				print("gateway hi",...)
				local h = c.upward.cmd.hi("gateway say hi")
				h.onAck = function(...) print("gateway ack", ...) end
				return "gateway.hi.ack"
			end,
			stop = function(...)
				return network.upward, ...
			end,
		}
		s = s or c
		-- c:addPrivilege("cmd", cmd)
	end)
end
local fps = 0
local minf
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
		os.execute("title gate fps = "..fps.."/"..minf..
			" r/w = "..network._status.receives.."/"..network._status.sends..
			" m = "..m.."/"..maxm..
			" rb/wb = "..rb.."/"..wb)
		network._status.receives = 0
		network._status.sends = 0
		time = os.clock()
		fps = 0
	end
end
