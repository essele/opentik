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
-- Maintain the lookup for system interface in the /interface (_if_lookup) section
-- so that we can map from interface events back to the correct item in the cf.
--
local function ci_postprocess(path, ci, going)
	local uniq = ci._uniq
	local base = CONFIG["/interface"]
	local map = (not going and { ["path"] = path, ["uniq"] = uniq }) or nil

	base._if_lookup = base._if_lookup or {}
	base._if_lookup[ci._system_name] = map
end


--
-- This is a helper function that anyone can use to lookup the system
-- interface given the interface name
--
local function lookup(name)
	-- TODO: catch missing items
	print("LOOKUP for "..name)
	print("FOUND: "..CONFIG["/interface"].cf[name]._system_name)
	return CONFIG["/interface"].cf[name]._system_name
end

--
--
--
lib.cf.register("/interface", {
	["fields"] = {
		["name"] = { 
			uniq = true, 
			default=""
		},
		["default-name"] = { 	
			readonly = true, 
			default = function(_, ci) return ci._orig_name end,
			prep = function(_, ci)
							if ci.name == ci._orig_name then return nil end
							return ci._orig_name
						end
		 },
		["disabled"] = { 
			default = false,
			prep = false,
		},
		["mtu"] = { 
			restart = true, 
			default = 87654,
		},
		["type"] = { 
			readonly = true, 
			default = "",
		},
	},
	
	["flags"] = {
		{ name = "dynamic", field = "_dynamic", flag = "D", pos = 1 },
		{ name = "disabled", field = "disabled", flag = "X", pos = 2 },
		{ name = "running", field = "_running", flag = "R", pos = 2 },
		{ name = "slave", field = "_slave", flag = "S", pos = 3 },
	},

	["options"] = {
		["can-delete"] = false,			-- can't delete ether interfaces
		["can-disable"] = true,			-- can disable them though
		["field-order"] = { "name", "default-name", "disabled", "mtu", "type" }
	},
})

return {
	ci_postprocess = ci_postprocess,
	lookup = lookup
}

