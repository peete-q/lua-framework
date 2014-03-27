
local _runnings = {}

function coroutine.run(f)
	local co = coroutine.create(f)
	_runnings[co] = co
	coroutine.resume(co)
	return co
end

function coroutine.stop(co)
	_runnings[co] = nil
end

function coroutine.step()
	local t = table.copy(_runnings)
	for k, v in pairs(t) do
		if coroutine.status(v) == "dead" then
			_runnings[k] = nil
		else
			local ok, err = coroutine.resume(v)
			if not ok then
				_runnings[k] = nil
				print(err)
			end
		end
	end
end