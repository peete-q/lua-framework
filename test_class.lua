dofile 'basic.lua'

local A = class 'A' define {
	a = 'A.a',
	b = {
		c = 'A.b.c'
	},
	f = function(self, ...)
		print('A.f', self.a, self.b, A.b, self.b.c, ...)
	end,
}
local a = A()

local B = class 'B' inherit 'A' define {
	a = 'B.a',
	f = function(self, ...)
		self.__base:f(...)
		print('B.f', self.a, self.b, B.b, self.b.c, ...)
	end,
}
local b = B()
b.b.c = 'b.b.c'
local b2 = b:__clone()

local C = class 'C' inherit 'B' define {
	b = {
		c = 'C.b.c'
	},
	f = function(self, ...)
		self.__base:f(...)
		print('C.f', self.a, self.b, C.b, self.b.c, ...)
	end,
}
local c = C()

print '-----------'
a:f('a')
print '-----------'
b:f('b')
print '-----------'
b.__base:f('b')
print '-----------'
c:f('c')
print '-----------'
c.__base:f('c')
c.__base.__base:f('c')
print(c.a, c.__base.a, c.__base.__base.a)
c.__base.a = 'change:c.__base.a'
print(c.a, c.__base.a, c.__base.__base.a)
print(c.b.c, c.__base.b.c, c.__base.__base.b.c)
print '-----------'
print(b.a, b.b, b.b.c)
print(b2.a, b2.b, b2.b.c)
