
timer = {
  __type = "timer",
}
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
local _instance = {
	__type = "timer.instance",
}
function _instance.restart(self, span, cb)
	self:stop()
	_counter = _counter + 1
	self._site = _query(span)
	self._site[self] = self
end
function _instance.stop(self)
	if self._site and self._site[self] then
		self._site[self] = nil
		self._site = nil
		_counter = _counter - 1
	end
end
function _instance.running(self)
	return self._site ~= nil
end

function timer.clock()
	return os.clock()
end
function timer.new(span, cb)
	local instance = {
		__type = "timer.instance",
		span = span,
		ring = timer.clock() + span,
		cb = cb,
		counter = _counter,
		restart = _instance.restart,
		stop = _instance.stop,
		running = _instance.running,
	}
	if span and cb then
		instance:start(span, cb)
	end
	return instance
end
function timer.step()
	local now = timer.clock()
	for i, q in ipairs(_queue) do
		if q.now < now then
			q.now = now + q.span
			for k, v in pairs(q.task) do
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
