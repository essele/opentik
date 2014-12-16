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

function callme(changes)
	print("Hello From Interface")

	local state = process_changes(changes, "interface/ethernet/")

	for _,v in ipairs(state.added) do print("Added: "..v) end
	for _,v in ipairs(state.removed) do print("Removed: "..v) end
	for _,v in ipairs(state.changed) do print("Changed: "..v) end
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
-- Main interface config definition
--
master["interface"] = {}
master["interface/ethernet"] = 				{ ["function"] = callme,
								 			  ["depends"] = { "iptables" }, 
											  ["with_children"] = 1 }

master["interface/ethernet/*"] = 			{ ["style"] = "ethernet_if" }
master["interface/ethernet/*/ip"] = 		{ ["type"] = "ipv4" }
master["interface/ethernet/*/mtu"] = 		{ ["type"] = "mtu" }
master["interface/ethernet/fred"] = { ["type"] = "ipv4" }
master["interface/ethernet/bill"] = { ["type"] = "ipv4" }


