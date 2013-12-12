dofile 'basic.lua'

local A = class 'A' define {
	a = 'A.a',
	b = {
		c = 'A.b.c'
	},
	f = function(self, ...)
		print('A.f', ...)
		self:g(...)
	end,
	g = function(self, ...)
		print('A.g', ...)
	end,
}
local a = A()

local B = class 'B' inherit 'A' define {
	a = 'B.a',
	f = function(self, ...)
		print('B.f', ...)
		A.f(self, ...)
	end,
	g = function(self, ...)
		print('B.g', ...)
		A.g(self, ...)
	end,
}
local b = B()

local C = class 'C' inherit 'B' define {
	b = {
		c = 'C.b.c'
	},
	f = function(self, ...)
		print('C.f', ...)
		B.f(self, ...)
	end,
	g = function(self, ...)
		print('C.g', ...)
		B.g(self, ...)
	end,
}
local c = C()
print(c)

print ('-----------')
a:f('a')
print ('-----------')
b:f('b')
print ('-----------')
c:f('c')

__classes = {}
local A = class 'A' define {
	a = 'A.a',
	b = {
		c = 'A.b.c'
	},
	f = function(self, ...)
		print('A.f', ...)
		self:g(...)
	end,
	g = function(self, ...)
		print('A.g', ...)
	end,
}
local a = A()

local B = class 'B' inherit 'A' define {
	a = 'B.a',
	f = function(self, ...)
		print('B.f', ...)
		self.__base:f(...)
	end,
	g = function(self, ...)
		print('B.g', ...)
		self.__base:g(...)
	end,
}
local b = B()

local C = class 'C' inherit 'B' define {
	b = {
		c = 'C.b.c'
	},
	f = function(self, ...)
		print('C.f', ...)
		self.__base:f(...)
	end,
	g = function(self, ...)
		print('C.g', ...)
		self.__base:g(...)
	end,
}
local c = C()
print(c)

print ('-----------', a)
a:f('a')
print ('-----------', b, b.__base)
b:f('b')
print ('-----------', c, c.__base, c.__base.__base)
c:f('c')

