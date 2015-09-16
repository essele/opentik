#!./luajit

x = 1
--y = 2
z = 3

a = x and not y and not p and z

print("a="..tostring(a))
