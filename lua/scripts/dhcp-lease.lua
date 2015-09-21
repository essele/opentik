#!/usr/bin/lua
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
-- This is a very simple script that pulls any relevant information from the
-- args passed and from the environment and then sends an event to the system
-- to cause the right action to happen.
--

--
-- Use our library autoloading mechanism
--
dofile("/opentik/lib/lib.lua")

--
-- Work out what we are doing
--
local action = arg[1] or "unknown"

--
-- Which fields do we want
--
local fields = { ["ip"] = true, ["mask"] = true, ["serverid"] = true, 
			 	 ["dns"] = true, ["lease"] = true, ["router"] = true, 
				 ["siaddr"] = true, ["interface"] = true, 
				 ["sname"] = true, ["mtu"] = true, ["broadcast"] = true,
				 ["routes"] = true, ["ntpsrv"] = true, ["message"] = true,
				 ["search"] = true, ["staticroutes"] = true }

local evmap = { ["bound"] = "add-lease", ["deconfig"] = "del-lease",
				["renew"] = "renew-lease", ["nak"] = "nak-lease",
				["leasefail"] = nil }

--
-- The basic event template
--
local ev = {
	event = evmap[action] or "unknown",
	path = "/ip/dhcp-client",
	action = action,
}

--
-- Get the whole environment, so we can pull out everything we need and copy
-- anything relevant to the event
--
local env = posix.stdlib.getenv()
for k,v in pairs(env) do if fields[k] or k:match("^opt") then ev[k] = v end end

--
-- Fixup the ones that have multiple entries
--
ev["dns"] = ev["dns"] and lib.util.split(ev["dns"], "%s")
ev["ntpsrv"] = ev["ntpsrv"] and lib.util.split(ev["ntpsrv"], "%s")
ev["router"] = ev["router"] and lib.util.split(ev["router"], "%s")

-- Send the event
lib.event.send(ev)

