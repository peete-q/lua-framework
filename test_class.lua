dofile 'basic.lua'

classA = class 'classA' define {
  a = 'classA.a',
	b = {
		c = 'classA.b.c'
	},
	f = function(self, ...)
		print('classA', ...)
	end,
}
a = classA()

classB = class 'classB' inherit 'classA' define {
	f = function(self, ...)
		self.__base:f(...)
		print('classB', ...)
	end,
}
b = classB()

classC = class 'classC' inherit 'classB' define {
	f = function(self, ...)
		self.__base:f(...)
		print('classC', ...)
	end,
}
c = classC()

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
