local lfs = require "lfs"
__entries = {}

function stdpath(entry)
	return string.gsub(entry, "\\", "/")
end

function import(entry)
	entry = stdpath(entry)
	local mode = lfs.attributes(entry, "mode")
	if mode == "file" then
		if not __entries[entry] then
			__entries[entry] = "loading"
			__entries[entry] = {dofile(entry)}
		elseif __entries[entry] == "loading" then
			error("import: loop or previous error loading '"..entry.."'")
		end
		return unpack(__entries[entry])
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

none = false
__type = type
function type(o)
	if __type(o) == "table" then
		return o.__type or __type(o)
	end
	if __type(o) == "userdata" and getmetatable(o) then
		return o.__type or __type(o)
	end
	return __type(o)
end

function field(o, name)
	if __type(o) == "table" then
		return o[name]
	end
	if __type(o) == "userdata" and getmetatable(o) then
		return o[name]
	end
end

function strict(object, access)
	access = access or "rw"
	local name = (object.__info or type(object))..":"..tostring(object)
	local meta = getmetatable(object)
	local newindex
	local index
	if meta then
		newindex = meta.__newindex
		index = meta.__index
	else
		meta = {}
		setmetatable(object, meta)
	end
	
	if string.find(access, "w") then
		if newindex then
			meta.__newindex = function(self, varname, value)
				if type(newindex(self, varname, value)) == "nil" then
					error("attempt to write undefined memmber '"..varname.."' of '"..name.."'")
				end
			end
		else
			meta.__newindex = function(self, varname, value)
				error("attempt to write undefined memmber '"..varname.."' of '"..name.."'")
			end
		end
	end
	if string.find(access, "r") then
		if index then
			meta.__index = function(self, varname, value)
				if type(index(self, varname, value)) == "nil" then
					error("attempt to read undefined memmber '"..varname.."' of '"..name.."'")
				end
			end
		else
			meta.__index = function(self, varname, value)
				error("attempt to read undefined memmber '"..varname.."' of '"..name.."'")
			end
		end
	end
	return object
end

function clone(source, depth, map)
	assert(type(source) == "table", "cannot clone nontable")
	assert(not source.__class, "cannot clone class")
	assert(not source.__object, "cannot clone object")
	
	local new
	if depth ~= 0 then
		if depth then
			depth = depth - 1
		end
		new = {}
		map = map or {}
		map[source] = source
		for k, v in pairs(source) do
			if type(v) == "table" then
				if map[v] then
					new[k] = map[v]
				else
					local tb = clone(v, depth, map)
					new[k] = tb
					map[v] = tb
				end
			else
				new[k] = v
			end
		end
	end
	return new
end

function copy(dest, source, cover, map)
	assert(dest)
	
	map = map or {}
	map[source] = source
	for k, v in pairs(source) do
		if cover or not dest[k] then
			if field(v, "__copy") then
				dest[k] = v:__copy()
			elseif type(v) == "table" and not v.__class and not v.__object then
				if map[v] then
					dest[k] = map[v]
				else
					local tb = clone(v, nil, map)
					dest[k] = tb
					map[v] = tb
				end
			else
				dest[k] = v
			end
		end
	end
end

__classes = {}
function class(name)
	assert(not __classes[name], "redefine class:"..name)
	
	local new = {
		__type = "class",
		__info = "class:"..name,
		__class = name,
	}
	
	local parent
	function inherit(name)
		assert(__classes[name], "inherit undefined class:"..name)
		parent = __classes[name]
	end
	
	function define(content)
		__classes[name] = new
		copy(new, content)
		
		if parent then
			new.__parent = parent
			copy(new, parent)
		end
		strict(new, "w")
		
		getmetatable(new).__call = function (self)
			local o = {
				__type = "object",
				__info = "object:"..self.__class,
				__object = self.__class,
			}
			copy(o, self)
			local this = o
			local base = {}
			while parent do
				base.__root = parent
				this.__base = base
				local dummy = {__base = {}}
				setmetatable(dummy, {__index = o, __newindex = o})
				setmetatable(base, {__index = function(self, key)
					local v = rawget(self, "__root")[key]
					if type(v) == "function" then
						return function(...)
							local arg = {...}
							if arg[1] == self then
								v(dummy, unpack(arg, 2))
							else
								v(...)
							end
						end
					end
					return v
				end})
				base = dummy.__base
				this = this.__base
				parent = parent.__parent
			end
			setmetatable(o, self)
			return o
		end
	end
	return new
end
