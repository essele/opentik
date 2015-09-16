--
-- 
--
--
--
--

Validators = {}

--
-- Validate a name...
--
function Validators.name(f, item, value)
	return (string.match(value, "^%a[%w_%-%+]*$") ~= nil)
end

--
-- Validate a number, if a range is provided then make
-- sure we check against it
--
function Validators.number(f, item, value)
	local n, min, max

	if(not string.match(value, "^%d+$")) then return false end
	value = tonumber(value)
	if(f.range) then
		min,max = string.match(f.range, "(%-?%d+)%-(%-?%d+)")
		min,max = tonumber(min),tonumber(max)
		if(min == nil) then return false end
		if(value < min or value > max) then return false end
	end
	return true
end

--
-- Validator for IPv4 addresses
--
function Validators.ipv4(table, field, s)
    local a,b,c,d = string.match(s, "^(%d+)%.(%d+)%.(%d+).(%d+)$")

    if(not a) then return false end
    a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)

    if(a>255 or b>255 or c>255 or d>255 ) then return false end
    return true
end

--
-- Validator for IP address with / prefix
--
function Validators.ipv4p(table, field, s)
    local a,b,c,d,p = string.match(s, "^(%d+)%.(%d+)%.(%d+).(%d+)/(%d+)$")

    if(not a) then return false end
    a, b, c, d, p = tonumber(a), tonumber(b), tonumber(c), tonumber(d), tonumber(p)

    if(a>255 or b>255 or c>255 or d>255 or p>32) then return false end
    return true
end

--
-- Validator for hostnams
--
function Validators.hostname(table, field, s)
    local m = string.match(s, "^%w[%w%.]+%w$")
    if(not m) then return false end
    return true
end


