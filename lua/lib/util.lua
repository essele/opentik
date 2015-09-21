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
-- Serialise a variable (most use for a table)
--
function serialise(t)
	local rc

	if type(t) == "table" then
		rc = "{"
		for k,v in pairs(t) do
			rc = rc .. ("["..serialise(k).."]="..serialise(v)..",")
		end
		return rc .. "}"
	elseif type(t) == "string" then
		return string.format('%q', t)
	else
		return tostring(t)
	end
end


--
-- Unserialise (just means executing the code)
--
function unserialise(v)
	return load("return "..v)()
end


--
-- Split a string into a table
--
local function split(str, sep)
	local rc = {}
	for tok in str:gmatch("([^"..sep.."]+)") do
		table.insert(rc, tok)
	end
	return rc
end




return {
	serialise = serialise,
	unserialise = unserialise,
	split = split,
}

