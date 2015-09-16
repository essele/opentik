#!./luajit

--
--
--
--
--
--


--
-- make sure we have the required parent in the master structure
--
if(not master["interface"]) then master["interface"] = {} end

--
-- our ethernet interface definition
--
master["interface"]["ethernet"] = {
	["*"] = {
		_function = "handle_eth",
		_listmode = "system",
		_syntax = "handle_eth_syntax",
		["name"] = {
			_type = "string"
		},
		["address"] = {
			_type = "ipv4_net",
			_syntax = "handle_address_syntax",
		},
		["duplex"] = {
			_type = "ipv4_net",
		},
		["speed"] = {
			_function = "handle_speed",
		}
	}
}

