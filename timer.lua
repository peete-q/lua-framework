
require "base_ext"

local timer = {}

local _counter = 0
local _queue = {
	{
		task = {},
		now = 0,
		span = 0,
		level = 0,
	},
	{
		task = {},
		now = 0,
		span = 1,
		level = 50,
	},
	{
		task = {},
		now = 0,
		span = 10,
		level = nil,
	},
}
local function _query(n)
	for i, v in ipairs(_queue) do
		if not v.level then
			return v.task
		end
		if n < v.level then
			return v.task
		end
	end
end

function _handle_start(self, span, cb)
	self:stop()
	_counter = _counter + 1
	self._site = _query(span)
	self._site[self] = self
end

function _handle_stop(self)
	if self._site and self._site[self] then
		self._site[self] = nil
		self._site = nil
		_counter = _counter - 1
	end
end

function _handle_running(self)
	return self._site ~= nil
end

function timer.clock()
	return os.clock()
end

function timer.new(span, cb)
	local o = {
		__tostring = ,
		span = span,
		ring = timer.clock() + span,
		cb = cb,
		counter = _counter,
		start = _handle_start,
		stop = _handle_stop,
		running = _handle_running,
	}
	o.__tostring = string.format("timer.handle (%s)", tostring(o))
	
	if span and cb then
		o:start(span, cb)
	end
	return o
end

function timer.step()
	local now = timer.clock()
	for i, q in ipairs(_queue) do
		if q.now < now then
			q.now = now + q.span
			local t = table.copy(q.task)
			for k, v in pairs(t) do
				if v.ring < now then
					v.cb()
					v.ring = now + v.span
				end
			end
		end
	end
end

function timer.counter()
	return _counter
end

function timer.empty()
	return _counter == 0
end

return timer