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
--------------------------------------------------------------------------------

--
-- see if a list contains a particular item
--
function is_in_list(list, item)
	for _,k in ipairs(list) do
		if(k == item) then return true end
	end
	return false
end

--
-- return the index of a match from a list
--
function find_in_list(list, item)
	for i = 1, #list do
		if(list[i] == item) then return i end
	end
	return nil
end

--
-- remove a particulare item from a list
--
function remove_from_list(list, item)
	local p = find_in_list(list, item)
	if(p) then table.remove(list, p) end
	return p
end

--
-- append a list onto a list
--
function append_list(a, b)
	for _,k in ipairs(b) do
		table.insert(a, k)
	end
end

--
-- recursively copy a table
--
function copy_table(t)
	local rc = {}
	for k, v in pairs(t) do
		if(type(v) == "table") then rc[k] = copy_table(v)
		else rc[k] = v end
	end
	return rc
end

--
-- return a hash of all the keys in the given tables
--
function keys(a, b, c)
	local rc = {}
	if(a) then for k,_ in pairs(a) do rc[k] = 1 end end
	if(b) then for k,_ in pairs(b) do rc[k] = 1 end end
	if(c) then for k,_ in pairs(c) do rc[k] = 1 end end
	return rc
end

--
-- compare things ... they should have the same elements and values
-- (recusively)
--
function are_the_same(a, b)
	if(type(a) ~= type(b)) then return false end

	if(type(a) == "table") then
		for k,_ in pairs(keys(a, b)) do
			if(not are_the_same(a[k], b[k])) then return false end
		end
	else
		if(a ~= b) then return false end
	end
	return true
end

--
-- remove any empty tables recursively (on the way back)
--
function clean_table(t)
	for k,v in pairs(t) do
		if(type(v) == "table") then 
			clean_table(v)
			if(not next(v)) then t[k] = nil end
		end
	end
end

