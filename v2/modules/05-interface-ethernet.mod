--
-- vi:filetype=lua
--

--
-- support for ip addresses with a /net number on the end, for
-- example: 10.2.3.4/24
--
function validator_ip4v_net(v)
end


--
-- primary function for handling basic ethernet configuration
--
--
function cf_ethernet(path, key, node, mnode)
	print("This is the cf_ethernet function")

	print("PATH="..tostring(path))


	for k,v in pairs(node) do
		print("  k="..k.." v="..tostring(v))
	end

	-- Option 1: DELETE ... if we are deleting an interface config then
	-- 			 we need to exit afterwards, we will be called again
	-- 			 for other operations.
	--
	if(node._deleted) then
		-- unconfigure the interface
		print("REMOVED INTERFACE " .. "eth" .. key)
		return true
	end

	-- Option 2: ADD ... we have setup a new interface, so this is a simple
	-- 			 creation with the right parameters
	--
	if(node._added) then
		print("NEW INTERFACE CREATED " .. "eth" .. key)
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
	["*"] = {
		_function = cf_ethernet,
		_listmode = "system",
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
		}
	},
}

