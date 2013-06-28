
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

function clone(source, depth, map)
	assert(type(source) == "table", "cannot clone nontable")
	assert(not source.__class, "cannot clone class")
	assert(not source.__object, "cannot clone object")
	if not depth or depth > 0 then
		local new = {}
		map = map or {}
		map[source] = source
		for k, v in pairs(source) do
			if type(v) == "table" then
				if map[v] then
					new[k] = map[v]
				else
					local tb = clone(v, depth - 1, map)
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

local function _base(parent)
	assert(parent.__class)
	local new = {
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
	setmetatable(new.__base, {__index = base_index(new)})
	
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
		local o = {
			__base = {
				__parent = self.__parent,
			},
			__parent = self,
		}
		setmetatable(o.__base, {__index = base_index(o)})
		setmetatable(o, {__index = index})
		return o
	end
	setmetatable(new, {__index = index, __call = call})
	return new
end

local function _base_now_index(self, key)
	local v = rawget(self, "__root")[key]
	if type(v) == "function" then
		return function(...)
			local arg = {...}
			if arg[1] == self then
				v(self, unpack(arg, 2))
			else
				v(...)
			end
		end
	end
	return v
end

local function _base_now(new, parent)
	assert(parent.__class)
	
	new.__base = {__root = parent, __base = parent.__base}
	new.__parent = parent
	copy(new, parent)
	setmetatable(new.__base, {__index = _base_now_index})
	return new
end

local function _base_now_call(self)
	local o = {
		__type = "object",
		__info = "object:"..self.__class,
		__base = {__root = self.__parent},
		__object = self.__class,
	}
	copy(o, self)
	setmetatable(o.__base, {__index = _base_now_index})
	setmetatable(o, {__index = self.__index, __newindex = self.__newindex})
	return o
end

__classes = {}
function class(name)
	assert(not __classes[name], "redeclare class:"..name)
	
	local new = {
		__type = "class",
		__info = "class:"..name,
		__class = name,
	}
	__classes[name] = new
	local parent
	function inherit(name)
		assert(__classes[name], "inherit undeclare class:"..name)
		parent = __classes[name]
	end
	function define(content)
		copy(new, content)
		if parent then
			_base_now(new, parent)
		end
		strict(new, "w")
		getmetatable(new).__call = _base_now_call
	end
	return new
end
