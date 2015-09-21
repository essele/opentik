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
-- Split a string into lines
--
local function lines(str)
	local rc = {}
	for line in string.gmatch(str, "(.-)\n") do table.insert(rc, line) end
	return rc
end

--
-- Create a templated configuration file
--
-- We work out what the leading space is on the first line
-- and remove that from every subsequent line.
--
-- Also we replace {{value}} where value appears in dict.
--
local function create_templated_file(name, template, dict)
	local input = lines(template, "\n")

	-- work out leading space
	local lead = input[1]:match("^(%s+)") or ""

	local i = 1
	while input[i] do
		local out = input[i]
		local var = out:match("{{([^}]+)}}")
		local vmatch = var and var:gsub("[%-%+]", "%%%1")

		if var then
			if dict[var] then
				if type(dict[var]) == "table" then
					for v = 1, #dict[var] do
						table.insert(input, i+v, (out:gsub("{{"..vmatch.."}}", dict[var][v])))
					end
					table.remove(input, i) 
				else
					input[i] = out:gsub("{{"..vmatch.."}}", dict[var])
				end
			else
				-- drop the line if we don't have the var
				table.remove(input, i) 
			end
		else
			input[i] = out
			i = i + 1
		end
	end

	-- remove the last line if it's just whitespace
	if input[#input]:match("^%s+$") then
		table.remove(input, #input)
	end
	
	local file = io.open(name, "w+")
	if not file then return nil end

	for _,line in ipairs(input) do
		file:write(line:gsub("^"..lead,"") .. "\n")
	end
	file:close()
	return true
end


return {
	template = create_templated_file,
}

