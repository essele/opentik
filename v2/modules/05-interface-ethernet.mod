--
-- vi:filetype=lua
--


--
-- Standard ipv4 addresses (eg. 1.2.3.4)
--
VALIDATOR["ipv4"] = function(v)
	local a,b,c,d = string.match(v, "^(%d+)%.(%d+)%.(%d+).(%d+)$")

	if(not a) then return false, "invalid ipv4 address" end
	a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)

	if(a>255 or b>255 or c>255 or d>255 ) then return false, "invalid ipv4 address" end
	return true
end

--
-- ipv4 addresses with a /net number on the end, (eg. 10.2.3.4/24)
--
VALIDATOR["ipv4_net"] = function(v)
	local a,b,c,d,e = string.match(v, "^(%d+)%.(%d+)%.(%d+).(%d+)/(%d+)$")

	if(not a) then return false, "invalid ipv4/net address" end
	a, b, c, d, e = tonumber(a), tonumber(b), tonumber(c), tonumber(d), tonumber(e)

	if(a>255 or b>255 or c>255 or d>255 or e>32 ) then return false, "invalid ipv4/net address" end
	return true
end

--
-- ipv4 addresses with an optional /net number on the end (either of the above)
--
VALIDATOR["ipv4_opt_net"] = function(v)
	local rc, rv, err

	rc, rv, err = pcall(VALIDATOR["ipv4"], v)
	if(rv) then return true end
	rc, rv, err = pcall(VALIDATOR["ipv4_net"], v)
	if(rv) then return true end
	return false, "invalid ipv4[/net] address"
end

--
-- primary function for handling basic ethernet configuration
--
--
local function cf_ethernet(path, key, config)
	print("This is the cf_ethernet function")

	print("PATH="..tostring(path))
	print("KEY="..tostring(key))
	dump(config)

	for key,value in each_added(config) do
		print("Added key="..key)
--		dump(value)
	end	

	-- Option 1: DELETE ... if we are deleting an interface config then
	-- 			 we need to exit afterwards, we will be called again
	-- 			 for other operations.
	--
	if(is_deleted(config)) then
		-- unconfigure the interface
		print("REMOVED INTERFACE " .. "eth" .. key)
		return true
	end

	-- Option 2: ADD ... we have setup a new interface, so this is a simple
	-- 			 creation with the right parameters
	--
	if(is_added(config)) then
		print("NEW INTERFACE CREATED " .. "eth" .. key)
--		error("oh dear")
		return true
	end

	-- Option 3: CHANGE ... we will have changed (or added/removed) an
	-- 			 option. 
	-- 
	-- TODO: is it easier just to go through the ADD process here as if
	-- 		 we were creating a new interface with these new settings?
	

	return true
end

--
-- make sure we have the required parent in the master structure
--
if(not CONFIG.master["interface"]) then CONFIG.master["interface"] = {} end

--
-- our ethernet interface definition
--
CONFIG.master["interface"]["ethernet"] = {
	--
	-- main section for instances of ethernet interfaces...
	--
	_keep_with_children = 1,
	["*"] = {
		_function = cf_ethernet,
		_syntax = "handle_eth_syntax",
		["name"] = {
			_type = "string"
		},
		["address"] = {
			_type = "ipv4_net",
			_syntax = "handle_address_syntax",
		},
		["secondaries"] = {
			_type = "list/ipv4_net",
			_syntax = "handle_address_syntax",
		},
		["duplex"] = {
			_type = "ipv4_net",
		},
		["speed"] = {
			_type = "interface_speed"
		},
	},
}

