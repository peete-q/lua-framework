
local network = require "proxy"
-- local profiler = require "ProFi"
local span = 0.0001
local run = true
local spend 

network._stats.receiver = function()
	if not spend then
		spend = os.clock()
		-- profiler:start()
	elseif network._stats.receives > 1000 and not record then
		print("spend", network._stats.receives, os.clock() - spend)
		-- profiler:stop()
		-- profiler:report("gp-"..os.time()..".txt")
		record = true
	end
end

-- gateway
local gateway, e = network.launchGateway("127.0.0.1",20001)
assert(gateway, e)
for i = 10001, 10051 do
	gateway:listen("127.0.0.1", i, function(c)
	end)
end

local now = os.clock()
local idx, fps, maxm = 0, 0, 0
local rs, ss, hd, rq, ors, oss, rd, st = 0, 0, 0, 0, 0, 0, 0, 0
while run do
	fps = fps + 1
	network.step(span)
	if os.clock() - now > 1 then
		idx = idx + 1
		local m = collectgarbage("count") / 1024
		maxm = m > maxm and m or maxm
		local info = string.format(
			"%d	fps = %d	m = %.2f/%.2f	rs/ss/hd/rq/or/os/rd/st = %d/%d/%d/%d/%d/%d/%d/%d",
			idx, fps, m, maxm,
			network._stats.receives - rs, network._stats.sends - ss,
			network._stats.handles - hd, network._stats.requests - rq,
			network._stats.overreceives - ors, network._stats.oversends - oss,
			network._stats.received - rd, network._stats.sent - st)
		print(info)
		rs, ss = network._stats.receives, network._stats.sends
		hd, rq = network._stats.handles, network._stats.requests
		ors, oss = network._stats.overreceives, network._stats.oversends
		rd, st = network._stats.received, network._stats.sent
		now = os.clock()
		fps = 0
	end
end
