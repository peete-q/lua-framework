
local lanes = require "lanes"
local socket = require "socket"
local network = require "network"
local span = 0.0000
local log = print
local print = function() end

local client = function(i)
	local spend
	-- client
	local network = require "network"
	network.connect("127.0.0.1", i, function(c, e)
		if not c then
			print("connect failed", e)
			return
		end
		local time = os.clock()
		c.cmd.start(time)
		network.step(span)
		for i = 1, 1000 do
			local h = c.cmd.hi("say hi")
			h.onAck = function(...)
				if i == 1000 then
					log("ack", os.clock() - time)
				end
			end
			c.cmd.hello("say hello")
			c.cmd.sub.a("sub.a")
			c:send("xxxxxxx")
			network.step(span)
		end
		spend = os.clock() - time
		-- c.cmd.stop(os.clock())
		log("spend", spend)
		while true do
			network.step(0.1)
		end
	end)
	return spend
end

local time = os.clock()
local c = {
	_privilege = {
		cmd = {
			hello = function(...)
				print("hello", ...)
			end,
		}
	}
}
for i = 1, 10000 do
	network._dorpc(c, {"@",{{"cmd","hello"},{}}})
end
log("dorpc spend", os.clock() - time)
-- client(10033)
local go = lanes.gen("*", client)

local n = 60
local tb = {}
for i = 1, n do
	tb[i] = go(math.random(10033, 10033))
end
local k = n
while k > 0 do
	for i = 1, n do
		if tb[i] and tb[i].status ~= "running" then
			print("["..i.."]", tb[i].status, "spend", tb[i][1])
			tb[i] = nil
			k = k - 1
		end
	end
	socket.sleep(1)
end