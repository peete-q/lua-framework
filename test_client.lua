
local lanes = require "lanes"
local socket = require "socket"
local network = require "network"
local stream = require "stream"
local span = 0.00001

local linda = lanes.linda()
local client = function(p, n)
	local spend
	-- client
	local network = require "network"
	local set = {}
	for i = 1, n do
		network.connect("127.0.0.1", p, function(c, e)
			if not c then
				print("connect failed", e)
				return
			end
			table.insert(set, c)
		end)
	end
	local now = os.clock()
	local dummy = function()
	end
	while true do
		for k, c in pairs(set) do
			local h = c.remote.cmd.hi("say hi")
			h.onAck = dummy
			local h = c.remote.cmd.hello("say hello")
			h.onAck = dummy
			local h = c.remote.cmd.sub.a("sub.a")
			h.onAck = dummy
			c:send(string.rep("x", 1024))
		end
		network.step(span)
		socket.sleep(span)
	end
	spend = os.clock() - now
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

local nb = 1
local tb = {}
for i = 1, nb do
	tb[i] = go(math.random(10001, 10051), 100)
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