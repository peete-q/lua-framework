
local network = require "proxy"
-- local profiler = require "ProFi"
local span = 0.001
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
for i = 10001, 10011 do
	gateway:listen("127.0.0.1", i, function(c)
	end)
end

local now = os.clock()
local idx, fps, maxm, backlogs = 0, 0, 0, 0
local rs, ss, rd, wt, re, se, rc, st = 0, 0, 0, 0, 0, 0, 0, 0
while run do
	fps = fps + 1
	network.step(span)
	backlogs = math.max(backlogs, network._stats.backlogs)
	if os.clock() - now > 1 then
		idx = idx + 1
		local m = collectgarbage("count") / 1024
		maxm = math.max(m, maxm)
		local info = string.format(
			"%d	fps = %d	m = %.2f/%.2f	rs/ss/rd/wt/re/se/rc/st = %d/%d/%d/%d/%d/%d/%.2f/%.2f backlogs = %.2f",
			idx, fps, m, maxm,
			network._stats.receives - rs, network._stats.sends - ss,
			network._stats.reads - rd, network._stats.writtens - wt,
			network._stats.receive_errors - re, network._stats.send_errors - se,
			(network._stats.received - rc) / 1024, (network._stats.sent - st) / 1024,
			backlogs)
		print(info)
		rs, ss = network._stats.receives, network._stats.sends
		rd, wt = network._stats.reads, network._stats.writtens
		re, se = network._stats.receive_errors, network._stats.send_errors
		rc, st = network._stats.received, network._stats.sent
		now = os.clock()
		fps = 0
		backlogs = 0
	end
end
