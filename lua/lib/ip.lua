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
-- This module provides a simple interface into the iproute2 command set
--
local function addr_add(ip, dev)
	local st = lib.run.execute("/sbin/ip", {"addr", "add", ip, "dev", dev }, nil, nil)
	return (st == 0)
end

local function addr_del(ip, dev)
	local st = lib.run.execute("/sbin/ip", {"addr", "del", ip, "dev", dev }, nil, nil)
	return (st == 0)
end

local function link_set(dev, ...)
	local st = lib.run.execute("/sbin/ip", {"link", "set", "dev", dev, ...})
	return (st == 0)
end


return {
	["addr"] = {
		["add"] = addr_add,
		["del"] = addr_del,
	},
	["route"] = {
	},
	["link"] = {
		["set"] = link_set,
	},
}



