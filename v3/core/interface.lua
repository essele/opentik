#!./luajit
--------------------------------------------------------------------------------
--  This file is part of OpenTik
--  Copyright (C) 2014 Lee Essen <lee.essen@nowonline.co.uk>
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
--	for any deleted
--		- unconfigure
--
--	for any changed
--		- reconfigure
--
--	for any new
--		- configure
--
--
--

local function ethernet_commit(changes)
	print("Hello From Interface")

	local state = process_changes(changes, "interface/ethernet")

	for v in each(state.added) do print("Added: "..v) end
	for v in each(state.removed) do print("Removed: "..v) end
	for v in each(state.changed) do print("Changed: "..v) end
	
	return true
end


--
-- If deleted then remove peer config
-- If added or modded then (re-)create the peer config
--
-- Work out if we need to restart anything.
--
local function pppoe_commit(changes)
	print("PPPOE")
	return true
end


--
-- For ethernet interfaces we expect a simple number, but it needs
-- to map to a real interface (or be a virtual)
--
VALIDATOR["ethernet_if"] = function(v)
	--
	-- TODO: once we know the numbers are ok, we need to test for a real
	--       interface.
	--
	local err = "interface numbers should be [nnn] or [nnn:nnn] only"
	if v:match("^%d+$") then return OK end
	if v:match("^%d+:$") then return PARTIAL, err end
	if v:match("^%d+:%d+$") then return OK end
	return FAIL, err
end

--
-- The MTU needs to be a sensible number
--
VALIDATOR["mtu"] = function(v)
	--
	-- TODO: check the proper range of MTU numbers, may need to support
	--       jumbo frames
	--
	if not v:match("^%d+$") then return FAIL, "mtu must be numeric only" end
	local mtu = tonumber(v)

	if mtu < 100 then return PARTIAL, "mtu must be above 100" end
	if mtu > 1500 then return FAIL, "mtu must be 1500 or less" end
	return OK
end

--
-- Convert any format into a full keypath, this is used by any function that
-- takes any interface as an argument. It allows complete flexibility in what
-- can be used.
--
function interface_path(interface)
	local t, i = interface:match("^interface/([^/]+)/%*?(%d+)$")
	if t then return string.format("interface/%s/*%i", t, i) end

	local t, i = interface:match("^([^/]+)/%*?(%d+)$")
	if t then return string.format("interface/%s/*%s", t, i) end

	local i = interface:match("^eth(%d+)$")
	if i then return string.format("interface/ethernet/*%s", i) end

	local i = interface:match("^pppoe(%d+)$")
	if i then return string.format("interface/pppoe/*%s", i) end

	return nil
end


--
-- Main interface config definition
--
master["interface"] = {}
master["interface/ethernet"] = 				{ ["commit"] = ethernet_commit,
								 			  ["depends"] = { "iptables" }, 
											  ["with_children"] = 1 }
master["interface/ethernet/*"] = 			{ ["style"] = "ethernet_if" }
master["interface/ethernet/*/ip"] = 		{ ["type"] = "ipv4" }
master["interface/ethernet/*/mtu"] = 		{ ["type"] = "mtu" }
--master["interface/ethernet/fred"] = { ["type"] = "ipv4" }
--master["interface/ethernet/bill"] = { ["type"] = "ipv4" }

master["interface/pppoe"] = 				{ ["commit"] = pppoe_commit,
											  ["depends"] = { "interface/ethernet" },
											  ["with_children"] = 1 }
master["interface/pppoe/*"] =				{ ["style"] = "pppoe_if" }
master["interface/pppoe/*/attach"] =		{ ["type"] = "ethernet_if" }
master["interface/pppoe/*/default-route"] =	{ ["type"] = "OK" }
master["interface/pppoe/*/mtu"] =			{ ["type"] = "mtu" }
master["interface/pppoe/*/user-id"] =		{ ["type"] = "OK" }
master["interface/pppoe/*/password"] =		{ ["type"] = "OK" }
	



