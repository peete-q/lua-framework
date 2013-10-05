
local lanes = require "lanes"
local socket = require "socket"
local network = require "network"
local stream = require "stream"
local span = 0.00001

local linda = lanes.linda()
local client = function(i, count)
	local spend
	-- client
	local network = require "network"
	
	network.connect("127.0.0.1", i, function(c, e)
		if not c then
			print("connect failed", e)
			return
		end
		local now = os.clock()
		network.step(span)
		local dummy = function()
		end
		while not count or count > 0 do
			if count then
				count = count - 1
			end
			
			local h = c.cmd.hi("say hi")
			h.onAck = dummy
			local h = c.cmd.hello("say hello")
			h.onAck = dummy
			local h = c.cmd.sub.a("sub.a")
			h.onAck = dummy
			c:send(string.rep("x", 1024))
			network.step(span)
			socket.sleep(0.001)
		end
		spend = os.clock() - now
		while true do
			network.step(span)
		end
	end)
	return spend
end

local now = os.clock()
local c = {
	_privilege = {
		cmd = {
			hello = function(...)
			end,
		}
	}
}

local s = stream.new()
s:write({"cmd","hello"}, {"dummy say hello"})
for i = 1, 10000 do
	s:seek(0)
	network._connection._dorpc(c, s, 2)
end
print("dorpc spend", os.clock() - now)
local go = lanes.gen("*", client)

local nb = 10
local tb = {}
for i = 1, nb do
	tb[i] = go(math.random(10001, 10051), nil)
	socket.sleep(0.1)
end
local k = nb
while k > 0 do
	for i = 1, nb do
		if tb[i] and tb[i].status ~= "running" then
			print("["..i.."]", tb[i].status, "spend", tb[i][1])
			tb[i] = nil
			k = k - 1
		end
	end
	socket.sleep(0.1)
end