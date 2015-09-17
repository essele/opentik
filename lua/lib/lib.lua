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

-- ==============================================================================
--
-- Requiring this library will cause subsequent modules to be loaded on demand
-- into the lib table.
--
-- We have our own searchpath (/opentik and .) to support operations on our
-- host machine or the target
--
-- ==============================================================================

local searchlist = { "/opentik", "." }

--
-- An __index function that allows references to table values to cause the
-- lib to be loaded from the relevant directory.
--
local function set_loader(table, dir)
	setmetatable(table, { __index = function(v, name)
		local file, filename

		print("Autoloading module: "..name.." ["..dir.."]")
		for _,p in pairs(searchlist) do
			filename = p .. "/" .. dir .. "/"..name..".lua"
			file = io.open(filename, "rb")
			if file then break end
		end
			
		if file then
			rawset(v, name, assert(load(assert(file:read("*a")), filename))() or {})
			return rawget(v, name)
		else
			assert(false, "module not found: "..filename)
		end
	end })
	return table
end

--
-- An equivalent loader for the posix modules, so they get loaded on demand
--
local function posixloader(v, name)
	print("Autoloading posix module: "..name)
	local path = v.__base .. "." .. name
	local i

	--
	-- Special case to avoid calling sys.lua
	--
	if path == "posix.sys" then
		i = {}
	else
		i = require(path)
	end

	i.__base = path
	setmetatable(i, { __index = posixloader })
	rawset(v, name, i)
	return i
end

--
-- Setup autoloading for lib and core
--
lib = set_loader({}, "lib")
core = set_loader({}, "core")

--
-- Setup autoloading for posix
--
posix = { __base = "posix" }
setmetatable(posix, { __index = posixloader } )

--
-- Load in the constants
--
-- _ = lib.const

