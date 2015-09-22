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
-- We have an interface dependency (probably) if the gateway is an interface device
-- (or more correctly isn't an ip address)
--
local function route_dependencies()
	-- todo: handle non interface version
--	return { ["gateway"] = { path = "/interface/ethernet", uniq = ci["gateway"], needrunning = false }, }
	return {}
end


--
-- Stop route ... 
--
local function stop_route(path, ci)
--	local dev = core.interface.lookupbyname(ci.interface)

--	lib.ip.addr.del(ci.address, dev)
end

--
-- Start route...
--
local function start_route(path, ci)
--	local dev = core.interface.lookupbyname(ci.interface)

--	lib.ip.addr.add(ci.address, dev)
end



--
-- Pull out the set of routes from the system routing table and turn them
-- into a set on entries that have a similar format to our live data
--
local function system_routes()
	--
	-- Pull out the basic routes list from iproute2
	--
	local st, routes = lib.run.execute("/sbin/ip", { "-4", "route", "show", "table", "all" })

	--
	-- Add the "unicase" keyword to ones starting with an address
	--
	for i,r in ipairs(routes) do
		local entry = {}

		--
		-- Process the entry and split it into key/value pairs
		--
		r:gsub("default", "0.0.0.0/0"):gsub("^([%d%./]+)%s", "unicast %1 ")
			:gsub("%s([%d%./]+)%s", " dst-address %1 ",1):gsub("^", "type ")
			:gsub(" src ", " pref-src "):gsub(" table ", " routing-mark ")
				:gsub("([^%s]+)%s+([^%s]+)", function(k,v) entry[k] = v end)

		routes[i] = nil
		if entry.type == "unicast" or entry.type == "prohibit" 
		or entry.type == "blackhole" or entry.type == "unreachable" then
			-- ensure we have a valid netmask, sort out the table, and see if its connected
			entry["dst-address"] = entry["dst-address"] .. ((not entry["dst-address"]:match("/") and "/32") or "")
			if entry.proto == "kernel" then
				entry._connected = true
				entry.distance = 0
			end

			-- clean out the bits we don't need
			entry.proto = nil
			entry.scope = nil
			entry.metric = nil

			-- set the flags for the special cases
			if entry.type == "prohibit" or entry.type == "blackhole" or entry.type == "unreachable" then
				entry["_"..entry.type] = true
			elseif entry.via then
				entry["gateway-status"] = entry["via"] .. " reachable via " .. entry["dev"]
				entry["gateway"] = entry.via
			else
				entry["gateway-status"] = entry["dev"] .. " reachable"
				entry["gateway"] = entry["dev"]
			end
			entry.via = nil
			entry.dev = nil

			-- TODO: routing mark name lookup
			-- TODO: proper interface name lookup (for gateway-status)

			-- store with a uniq key
			local key = string.format("%s@%s", entry["dst-address"], entry["routing-mark"] or "main")
			routes[key] = entry
		end
	end
	return routes
end



--
-- Build a list of routes that we think should be deployed based on dst-address/routing-mark/type and
-- the distance ... so we only pick the one with the smallest distance in each case.
--
local function route_list()
	local base = CONFIG["/ip/route"]
	local live = base.live
	local system = system_routes()

	-- Rework our list building a table for each uniq dst/mark/type combination with the lowest
	-- distance only stored, we remove all the external stuff as we process.
	local dests = {}
	for uniq,rt in pairs(live) do
		if rt._external then
			live[uniq] = nil
		else
			local dest = string.format("%s@%s", rt["dst-address"], rt["routing-mark"])
			local sysdist = (system[dest] and system[dest].distance) or 256
			local prevdist = (dests[dest] and dests[dest].distnace) or 256
			rt.active = nil

			if rt["distance"] < sysdist and rt["distance"] < prevdist then
				dests[dest] = rt
			end
		end
	end

	-- At this point we should have the list of all the active routes, we can run through
	-- our system routes ensuring our stuff is properly installed.

	for dest,rt in pairs(dests) do
		local sysdest = system[dest]

		print("Looking at "..dest)

		if not sysdest then
			print("need to add to system")
		elseif sysdest.type ~= rt.type or sysdest.gateway ~= rt.gateway then
			print("need to change del/add")
			-- TODO: copy status over
		else
			print("route seems to be there ok")
			-- TODO: copy status over
		end
		rt.active = true		-- mark route active
		system[dest] = nil		-- remove from system list
		-- TODO: status?
	end	

	-- Now we can add any remaining system routes as external live ones
	for _,rt in pairs(system) do
		rt._external = true
		rt._dynamic = true
		rt.active = true
		lib.cf.live("/ip/route", nil, rt)
	end

	-- Install any that are missing

	-- QUESTION: do we reconcile against live data somehow?	
	
	print(lib.cf.dump(CONFIG["/ip/route"].live))
end



lib.cf.register("/ip/route", {
	["fields"] = {
		["dst-address"] = { default = "0.0.0.0/0" },
		["routing-mark"] = { default = "main" },
		["scope"] = { default = 30 },
		["type"] = { default = "unicast" },
		["pref-src"] = { default = "" },
		["gateway"] = { default = "" },
		["distance"] = { default = 5 },
		["disabled"] = { default = false },
	},
	["dependencies"] = route_dependencies,

	-- TODO: get flags right
	["flags"] = {
		{ name = "disabled", field = "disabled", flag = "X", pos = 1 },
		{ name = "active", field = "active", flag = "A", pos = 1 },
		{ name = "dynamic", field = "_dynamic", flag = "D", pos = 2 },
		{ name = "connect", field = "_connected", flag = "C", pos = 3 },
		{ name = "static", field = "static", flag = "S", pos = 3 },
		{ name = "blackhole", field = "_blackhole", flag = "B", pos = 4 },
		{ name = "unreachable", field = "_unreachable", flag = "U", pos = 4 },
		{ name = "prohibit", field = "_prohibit", flag = "P", pos = 4 },
	},

	["options"] = {
		["ci-post-process"] = nil,
		["stop"] = stop_route,
		["start"] = start_route,
		["can-delete"] = true,
		["can-disable"] = true,
		["field-order"] = { "dst-address", "gateway", "routing-mark", "scope", "type", "pref-src" },
	},
})

return {
	route_list = route_list,
}
