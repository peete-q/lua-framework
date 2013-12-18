
local socket = require "socket"
local network = require "network"
local stream = require "stream"
local span = 0.001

local dummy = function()
end
local set = {}
local connect = function(p, n)
	-- client
	local network = require "network"
	for i = 1, n do
		network.connect("127.0.0.1", p, function(c, e)
			if not c then
				print("connect failed", e)
				return
			end
			table.insert(set, c)
			
			local function say_hi()
				local h = c.remote.cmd.hi("say hi")
				h.onAck = say_hi
			end
			local function say_hello()
				local h = c.remote.cmd.hi("say hello")
				h.onAck = say_hello
			end
			local function sub_a()
				local h = c.remote.cmd.hi("sub.a")
				h.onAck = sub_a
				c:send(string.rep("x", 1024))
			end
			say_hi()
			say_hello()
			sub_a()
		end)
	end
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
print("dorpc", os.clock() - now)

print "init ..."
connect(10001, 1)
print "inited"

local now = os.clock()
local idx, fps, maxm, backlogs = 0, 0, 0, 0
local rs, ss, rd, wt, re, se, rc, st = 0, 0, 0, 0, 0, 0, 0, 0
while true do
	fps = fps + 1
    -- for k, c in pairs(set) do
		-- local h = c.remote.cmd.hi("say hi")
		-- h.onAck = dummy
		-- local h = c.remote.cmd.hello("say hello")
		-- h.onAck = dummy
		-- local h = c.remote.cmd.sub.a("sub.a")
		-- h.onAck = dummy
		-- c:send(string.rep("x", 1024))
    -- end
	network.step(span)
	backlogs = math.max(backlogs, network._stats.backlogs / 1024)
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
