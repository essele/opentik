--------------------------------------------------------------------------------
--  This file is part of OpenTik
--  Copyright (C) 2014,15 Lee Essen <lee.essen@nowonline.co.uk>
--
--  This program is free software: you can redistribute it and/or modify
--  it under the terms of the GNU General Public License as published by
--  the Free Software Foundation, either version 3 of the License, or
--  (at your option) any later version.
--
--  This program is distributed in the hope that it will be useful,
--  but WITHOUT ANY WARRANTY; without even the implied warranty of
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--  GNU General Public License for more details.
--
--  You should have received a copy of the GNU General Public License
--  along with this program.  If not, see <http://www.gnu.org/licenses/>.
------------------------------------------------------------------------------



--
-- Stop address ... just remove the address from the interface
--
local function stop_address(path, ci)
	local dev = core.interface.lookupbyname(ci.interface)

	lib.ip.addr.del(ci.address, dev)
end

--
-- Start address ... just add the address to the interface
--
local function start_address(path, ci)
	local dev = core.interface.lookupbyname(ci.interface)

	lib.ip.addr.add(ci.address, dev)
end

--
--
--
lib.cf.register("/ip/address", {
	["fields"] = {
		["address"] = { 
			default="",
		},
		["interface"] = { 	
			readonly = true, 
			default = ""
		 },
		["disabled"] = { 
			default = false,
			prep = false,
		},
		["netmask"] = { 
			default = "0.0.0.0",
		},
		["network"] = { 
			default = "0.0.0.0",
			prep = false,
		},
		["actual-interface"] = {
			default = "",
		},
		["uniq"] = {
			uniq = function(_, ci) return string.format("%s@%s", ci.address, ci.interface) end,
		},
	},

	["dependencies"] = {
		["interface"] = { path = "/interface/ethernet", needrunning = false },
	},
	
	["flags"] = {
		{ name = "disabled", field = "disabled", flag = "X", pos = 1 },
		{ name = "invalid", field = "_invalid", flag = "I", pos = 1 },
		{ name = "dynamic", field = "_dynamic", flag = "D", pos = 1 },
	},

	["options"] = {
		["ci-post-process"] = nil,
		["stop"] = stop_address,
		["start"] = start_address,
		["can-delete"] = true,
		["can-disable"] = true,
		["field-order"] = { "address", "network", "interface", "actual-interface" }
	},
})

