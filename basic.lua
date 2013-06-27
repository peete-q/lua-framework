local lfs = require "lfs"
local _loaded = {}

function stdpath(entry)
  return string.gsub(entry, "\\", "/")
end

function import(entry)
	entry = stdpath(entry)
	local mode = lfs.attributes(entry, "mode")
	if mode == "file" then
		if not _loaded[entry] then
			_loaded[entry] = "loading"
			_loaded[entry] = {dofile(entry)}
		elseif _loaded[entry] == "loading" then
			error("import: loop or previous error loading '"..entry.."'")
		end
		return unpack(_loaded[entry])
	elseif mode == "directory" then
		local exports = {}
		for e in lfs.dir(entry) do
			e = entry.."/"..e
			if lfs.attributes(e, "mode") == "file" then
				local tb = {import(e)}
				for i, v in ipairs(tb) do
					table.insert(exports, v)
				end
			end
		end
		return unpack(exports)
	else
		error("import: can not found '"..entry.."'")
	end
end

function strict(object, name, access)
	name = name or tostring(object)
	access = access or "rw"
	assert(not getmetatable(object), "attemp to strict '"..name.."' with metatable")
	local meta = {}
	if string.find(access, "w") then
		meta.__newindex = function(self, varname, value)
			error("attempt to write undeclared memmber '"..varname.."' of '"..name.."'")
		end
	end
	if string.find(access, "r") then
		meta.__index = function(self, varname, value)
			error("attempt to read undeclared memmber '"..varname.."' of '"..name.."'")
		end
	end
	setmetatable(object, meta)
	return object
end

function clone(parent, map)
	local new = {}
	map = map or {}
	map[parent] = parent
	for k, v in pairs(parent) do
		if type(v) == "table" then
			if map[v] then
				new[k] = map[v]
			else
				local tb = clone(v, map)
				new[k] = tb
				map[v] = tb
			end
		elseif type(v) == "userdata" and v.clone then
			new[k] = v:clone()
		else
			new[k] = v
		end
	end
	return new
end

function base(parent)
	assert(parent, debug.traceback())
	local tb = {
		__base = {
			__parent = parent,
		},
		__parent = parent,
	}
	
	local function base_index(self)
		local tb = self
		return function(self, name)
			local v = rawget(self, "__parent")[name]
			if type(v) == "function" then
				return function(...)
					local t = {...}
					if t[1] == self then
						local dummy = {
							__base = self.__base
						}
						setmetatable(dummy, {__index = tb, __newindex = tb})
						v(dummy, unpack(t, 2))
					else
						v(...)
					end
				end
			end
			if type(v) == "table" then
				local dummy = {
					__parent = v,
				}
				rawset(self, name, dummy)
				setmetatable(dummy, {__index = base_index})
				return dummy
			end
			return v
		end
	end
	setmetatable(tb.__base, {__index = base_index(tb)})
	
	local function index(self, name)
		local v = rawget(self, "__parent")[name]
		if type(v) == "table" then
			local dummy = {__parent = v}
			rawset(self, name, dummy)
			setmetatable(dummy, {__index = index})
			return dummy
		end
		return v
	end
	
	local function call(self)
		local tb = {
			__base = {
				__parent = self.__parent,
			},
			__parent = self,
		}
		setmetatable(tb.__base, {__index = base_index(tb)})
		setmetatable(tb, {__index = index})
		return tb
	end
	setmetatable(tb, {__index = index, __call = call})
	return tb
end
