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
local function stop_dhcp(path, ci)
	local dev = core.interface.lookup(ci.interface)

end

--
-- Start address ... just add the address to the interface
--
local function start_dhcp(path, ci)
	local uniq = ci._uniq
	local dev = core.interface.lookup(ci.interface)
	local args = { 	"--interface", dev,
					"--script", "/opentik/dhc",
					"--release",
					"--foreground",
				}
	local pid = lib.run.background("/sbin/udhcpc", args)
	print("PID is "..pid)
	CONFIG[path].live[uniq]._pid = pid

	print(lib.cf.dump(CONFIG[path]))
end

--
-- DHCP Event ... called when we get an address
--
local function event_add_lease(e)
	print("Called with event add lease")
	print(lib.cf.dump(e))
end


--
--
--
lib.cf.register("/ip/dhcp-client", {
	["fields"] = {
		["add-default-route"] = { 
			default = true,
		},
		["client-id"] = {
			default = "",
		},
		["default-route-distance"] = {
			default = "",
		},
		["disabled"] = { 
			default = true,
			prep = false,
		},
		["host-name"] = {
			default = "",
		},
		["interface"] = { 	
			default = "",
			uniq = true,
		 },
		["use-peer-dns"] = { 
			default = true,
		},
		["use-peer-ntp"] = { 
			default = true,
		},
	},

	["dependencies"] = {
		["interface"] = { path = "/interface/ethernet", needrunning = true },
	},
	
	["flags"] = {
		{ name = "disabled", field = "disabled", flag = "X", pos = 1 },
		{ name = "invalid", field = "_invalid", flag = "I", pos = 1 },
	},

	["options"] = {
		["ci-post-process"] = nil,
		["stop"] = stop_dhcp,
		["start"] = start_dhcp,
		["can-delete"] = true,
		["can-disable"] = true,
		["field-order"] = { "interface", "add-default-route", "use-peer-dns", "use-peer-ntp",
								"client-id", "host-name" },
	},

	["events"] = {
		["add-lease"] = event_add_lease,
	},

})

