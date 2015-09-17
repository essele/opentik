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
--
--
lib.cf.register("/ip/address", {
	["fields"] = {
		["address"] = { 
			default=""
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
	},
	
	["flags"] = {
		{ name = "disabled", field = "disabled", flag = "X", pos = 1 },
		{ name = "invalid", field = "_invliad", flag = "I", pos = 1 },
		{ name = "dynamic", field = "_dynamic", flag = "D", pos = 1 },
	},

	["options"] = {
		["ci-post-process"] = nil,
		["can-delete"] = true,
		["can-disable"] = true,
		["field-order"] = { "address", "network", "interface", "actual-interface" }
	},
})

