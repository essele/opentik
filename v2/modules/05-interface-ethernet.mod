--
-- vi:filetype=lua
--

--
-- support for ip addresses with a /net number on the end, for
-- example: 10.2.3.4/24
--
local function validator_ip4v_net(v)
end



--
-- api calls
--

--
-- At the node level we may be entirely added or removed
--
local function is_added(config)
	local ac, dc = config.ac, config.dc

	if(dc and not ac) then return true end
	return false
end
local function is_deleted(config)
	local ac, dc = config.ac, config.dc

	if(ac and not dc) then return true end
	return false
end

--
-- For each item (fields and containers) we return an iterator covering
-- the ones that were added, remove or changed.
--
local function each_added(config)
	local ac, dc = config.ac or {}, config.dc or {}
	local last

	return function()
		while(1) do
			last = next(dc, last)
			if(not last) then return nil end
			if(not ac[last]) then return last, dc[last] end
		end
	end
end
local function each_deleted(config)
	local ac, dc = config.ac or {}, config.dc or {}
	local last

	return function()
		while(1) do
			last = next(ac, last)
			if(not last) then return nil end
			if(not dc[last]) then return last, ac[last] end
		end
	end
end
local function each_changed(config)
	local ac, dc = config.ac or {}, config.dc or {}
	local last

	return function()
		while(1) do
			last = next(dc, last)
			if(not last) then return nil end
			if(ac[last] and ac[last] ~= dc[last]) then return last, ac[last], dc[last] end
		end
	end
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

