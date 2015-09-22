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
-- Stop dhcp ... kill the process if it's running, that will cause the
-- address to be removed (if we have a valid lease)
--
local function stop_dhcp(path, ci)
	local base = CONFIG[path]
	local uniq = ci._uniq
	local live = base.live[uniq]
	local dev = core.interface.lookupbyname(ci.interface)

	if live._pid then
		print("would kill " .. live._pid)
		live._pid = nil
	end
	live["status"] = "stopped"
end

--
-- Start dhcp ... start the executable and save the pid into the live
-- structure
--
local function start_dhcp(path, ci)
	local base = CONFIG[path]
	local uniq = ci._uniq
	local live = base.live[uniq]
	local dev = core.interface.lookupbyname(ci.interface)
	local args = { 	"--interface", dev,
					"--script", "/opentik/scripts/dhcp-lease.lua",
					"--release",
					"--foreground" }
	local pid = lib.run.background("/sbin/udhcpc", args)
	print("PID is "..pid)
	live._pid = pid

	print(lib.cf.dump(CONFIG[path]))
end

--
-- DHCP Event ... called when we get an address, we update the live
-- structure, and then add the ipaddress etc.
--
local function event_add_lease(e)
	local base = CONFIG["/ip/dhcp-client"]
	local interface = core.interface.lookupbydev(e.interface)
	local live = base.live[interface]

	print("Called with event add lease")

	--
	-- Copy the relevant information into the live structure
	--
	live["address"] = e.ip .. "/" .. e.mask
	live["dhcp-server"] = e.serverid
	live["gateway"] = e.router and e.router[1]
	live["primary-dns"] = e.dns and e.dns[1]
	live["secondary-dns"] = e.dns and e.dns[2]
	live["primary-ntp"] = e.ntpsrv and e.ntpsrv[1]
	live["secondary-ntp"] = e.ntpsrv and e.ntpsrv[2]
	live["status"] = "bound"

	--
	-- Add the ip address to the interface
	--
	lib.ip.addr.add(live.address, e.interface)


	print(lib.cf.dump(live))

	-- TODO: dns
	-- TODO: ntp
	-- TODO: router
end

--
-- DHCP Event ... del-lease called before we start and then also
-- if we lose the lease. Ensure the live structure is clean and
-- remove the address if we have one.
--
local function event_del_lease(e)
	local base = CONFIG["/ip/dhcp-client"]
	local interface = core.interface.lookupbydev(e.interface)
	local live = base.live[interface]

	print("Called with event del lease")
	print(lib.cf.dump(e))

	if live.address then
		lib.ip.addr.del(live.address, e.interface)
	end

	live["address"] = nil
	live["dhcp-server"] = nil
	live["gateway"] = nil
	live["primary-dns"] = nil
	live["secondary-dns"] = nil
	live["primary-ntp"] = nil
	live["secondary-ntp"] = nil

	--
	-- TODO: If we are still running then what status is this
	-- really ... probably a request.
	--
	-- Could be a release, so probably need to track activity
	-- somewhere so we can do better with this (or set it in the previous place)
	--
	if live._pid then
		live["status"] = "requesting"
	end
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
		["del-lease"] = event_del_lease,
	},

})

