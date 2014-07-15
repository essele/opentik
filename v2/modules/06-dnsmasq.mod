--
-- vi:filetype=lua
--

--
-- Standard ipv4 addresses (eg. 1.2.3.4)
--
VALIDATOR["Xipv4"] = function(v)
	local a,b,c,d = string.match(v, "^(%d+)%.(%d+)%.(%d+).(%d+)$")

	if(not a) then return false, "invalid ipv4 address" end
	a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)

	if(a>255 or b>255 or c>255 or d>255 ) then return false, "invalid ipv4 address" end
	return true
end


--
-- primary function for handling basic ethernet configuration
--
--
local function cf_dnsmasq(path, key, config)
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
CONFIG.master["dnsmasq"] = {
	_hidden = 1,
	_function = cf_dnsmasq,
	["dns"] = {
		["resolvers"] = {
			_type = "list/ipv4"
		},
		["hosts"] = {
			["*"] = {
				["name"] = { _type = "hostname" },
				["ipv4"] = { _type = "ipv4" },
			}
		},
	},
	["dhcp"] = {
		["blag"] = {
			_type = "string"
		}
	}
}

CONFIG.master["dhcp"] = { _alias = "/dnsmasq/dns" }
CONFIG.master["dns"] = { _alias = "/dnsmasq/dhcp" }

