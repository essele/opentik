#!./luajit


--
-- Simple serialize/de-serialize interface
--

function is_array(o)
	if(type(o) ~= "table") then return false end
	local k = next(o)

	return (type(k) == "number")
end

function indent(i)
	return string.rep(" ", i)
end


function serialize(o, i)
	local op = ""
	local otype = type(o)
	
	local i = i or 0

	if(otype == "string") then
		op = op .. string.format("%q", o)
	elseif(otype == "number") then
		op = op .. o
	elseif(otype == "boolean") then
		op = op .. tostring(o)
	elseif(otype == "nil") then
		op = op .. "nil"
	elseif(otype == "table") then
		op = op .. "{\n"
		for k,v in pairs(o) do
			if(is_array(v)) then
				for x, vv in ipairs(v) do
					op = op .. indent(i+4) .. k .. " " .. serialize(vv, i+4) .. "\n"
				end
			else 
				op = op .. indent(i+4) .. k .. " " .. serialize(v, i+4) .. "\n"
			end
		end
		op = op .. indent(i) .. "}"
	end
	
	return op
end

x = {}
x.abc = 123
x.fff = 111

x.bill = { "one", "two", "three" }
x.joe = { one = 1, two = "root", bill = { x = 1, y= 2 }, three = "8.4" }

y = serialize(x)

print(":: [" .. y .. "]")
