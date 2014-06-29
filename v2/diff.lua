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
--------------------------------------------------------------------------------

package.path = "./lib/?.lua"
package.cpath = "./lib/?.so"

require("lfs")
require("base64")


--
-- Basic lua functions for showing differences between two tables
--

master = {
	["dns"] = {
		["resolvers"] = {
			_type = "list/ipv4"
		},
		["billy"] = {
			_type = "file/text"
		},
		["abc"] = {
			["yes"] = {
				_type = "fred"
			},
			["no"] = {
				_type = "bool"
			}
		}
	},
	["dhcp"] = {
		_keep_with_children = 1,
		["*"] = {
--			_label = "dhcp ",
			_order = { "fred", "bill" },
			["fred"] = { _type = "xx" },
			["bill"] = { _type = "xx" }
		},
		["blah"] = { _type = 45 },
		["blah2"] = { _type = 45 }
	},
	["x"] = { _type = "xx" }
}

one = {
	["dns"] = {
		resolvers = { "one", "two", "three" },
		billy = "hello herskjhfglskjhfg sdlfkjghs dflgkjhds flkjghds lfkghsdlkfjghsldkfjg sdlkfhg sdlkfhg sldkjfg lsdkfjhg lsdkfjhg sldkhfg lsdkfg lsdkfjhg sldkfjhgs ldkfjgh lskdfhg lskdfjhgl ksdfhgl sdkfhg lskdfhg lskdhfgl ksdjfg lkjsdadflkjhdlkjha dlfkjhas ldkjfhas ldkjfhal skdjfh laskjdhfl aksdjf laskdjf lasjdkhfl asdhfla ksdjf lasjdf lasdjf laskf laskjflaksjdhf laskjdhf lasjkdhfl aksjdhf laksjdhf laskdh lfkjasdff g",
		abc = {
			yes = 1, no = 2
		}
	},
	["dhcp"] = {
		["a"] = {
			fred = 1,
			bill = 2,
			comment = { "one", "two", "", "four big long comment line" }
		},
		["b"] = {
			fred = 50
		},
		["blah"] = 45,
		["blah2"] = "ab"
	}
}

two = {
	["x"] = 1,
	["dhcp"] = {
		["a"] = {
			fred = 5
		}
	},
	["dns"] = {
		resolvers = { "four" }
	}
}


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
-- compare things ... they should have the same elements and values
-- (recusively)
--
function are_the_same(a, b)
	if(type(a) ~= type(b)) then return false end

	if(type(a) == "table") then
		local keys = {}
		for k,_ in pairs(a) do keys[k] = 1 end
		for k,_ in pairs(b) do keys[k] = 1 end

		for k,_ in pairs(keys) do
			if(not are_the_same(a[k], b[k])) then return false end
		end
	else
		if(a ~= b) then return false end
	end
	return true
end

--
-- standard formatting is "[mode] [indent][label] [value]"
--
function op(mode, indent, label, value)
	local rh = (value and (label .. " " .. value)) or label
	
	return mode .. string.rep(" ", indent+1) .. rh .. "\n"
end

--
-- dump a table for debugging
--
function dump(t, i)
	i = i or 0
	for k, v in pairs(t) do
		print(string.rep(" ", i)..k.."="..tostring(v))
		if(type(v) == "table") then
			dump(v, i+4)
		end
	end
end

--
-- returns an iterator that cycles through each field listed in the
-- provided master. The _fields directive is created by the prepare_master
-- function
--
function each_field(m)
	local i = 0
	return function()
		i = i + 1
		local k = m._fields[i]

		if(not k) then return nil end
		return k, m[k]._type
	end
end

--
-- returns an iterator that finds any container contained within a
-- or b, it uses master to work out if it's a container of not. They
-- are iterated in _order order, with wildcards alphabetically
--
function each_container(a, b, m)
	-- build list of containers from a and b... work out if they are wildcards...
	local keys = {}
	local wildcards = {}
	local clist = {}
	if(a) then for k,_ in pairs(a) do keys[k] = 1 end end
	if(b) then for k,_ in pairs(b) do keys[k] = 1 end end
	for k,_ in pairs(keys) do 
		if(m[k] and not m[k]._type) then	-- container
			table.insert(clist, k)
		elseif(not m[k]) then				-- wildcard
			table.insert(wildcards, k)
		end
	end
	table.sort(wildcards)
	table.sort(clist)
		
	-- now create the list using the order field...
	local containers = {}
	for _,k in ipairs(m._containers) do
		if(k == "*") then 
			append_list(containers, wildcards)
		elseif(is_in_list(clist, k)) then
			table.insert(containers, k)
			remove_from_list(clist, k)
		end
	end
	append_list(containers, clist)

	-- create the iterator function...
	local i = 0
	return function()
		i = i + 1
		return containers[i]
	end
end

--
-- given two lists (a and b), we process up to the first match that we find where
-- an item from b is in a. At that point we return any prior items from a as deleted,
-- any items from b that are added, and then the matching item.
--
function list_first_match(a, b)
	local added = {}
	local removed = {}
	local matched = nil

	while(b[1]) do
		local i = find_in_list(a, b[1])
		if(i) then
			for d = 1, i-1 do
				table.insert(removed, a[1])
				table.remove(a, 1)
			end
			matched = b[1]
			table.remove(a, 1)
			table.remove(b, 1)
			break
		else
			table.insert(added, b[1])
			table.remove(b, 1)
		end
	end

	-- if we didn't match anything, then all in (a) is removed...	
	if(not matched) then while(a[1]) do table.insert(removed, a[1]) table.remove(a, 1) end end

	-- now prepare ... removed, added and then match
	local op = {}
	for _,k in ipairs(removed) do table.insert(op, { item=k, op = "-" }) end
	for _,k in ipairs(added) do table.insert(op, { item=k, op = "+" }) end
	if(matched) then table.insert(op, { item=matched, op = " " }) end
	return op
end

--
-- Handle the display of both dinay and text files
--
function show_file(mode, ftype, k, value, indent, dump)
	local rc = ""
	ftype = string.sub(ftype, 6)

	rc = rc .. op(mode, indent, k, "<" .. ftype .. ">")
	if(ftype == "binary") then
		local binary = enc(value)
		for i=1, #binary, 76 do
			rc = rc .. op(mode, indent+4, string.sub(binary, i, i+75))
			if(not dump) then
				if(i >= 76*3) then
					rc = rc .. op(mode, indent+4, "... (total " .. #binary .. " bytes)")
					break
				end
			end
		end
	elseif(ftype == "text") then
		local lc = 0
		for line in (value .. "\n"):gmatch("(.-)\n") do
			rc = rc .. op(mode, indent+4, "|" .. line)
			if(not dump) then
				lc = lc + 1
				if(lc >= 4) then
					rc = rc .. op(mode, indent+4, "... <more>")
					break
				end
			end
		end
		if(dump) then rc = rc .. op(mode, indent+4, "<eof>") end
	end
	return rc
end

--
-- we keep calling the list_first_match() function to work through
-- both lists ... we do change the lists, so we need to copy them first
--
function show_list(aa, bb, label, indent, dump)
	local a = copy_table(aa or {})
	local b = copy_table(bb or {})
	local rc = ""

	while(a[1] or b[1]) do
		local l = list_first_match(a, b)
		for _,k in ipairs(l) do
			local mode = (dump and " ") or k.op

			rc = rc .. op(mode, indent, label, k.item)
		end
	end
	return rc
end

--
-- Display the non-container items from within a given node and
-- show if they are added/removed/changed
--
function show_fields(a, b, master, indent, dump)
	local rc = ""

	for k, ftype in each_field(master) do
		local av = a and a[k]
		local bv = b and b[k]
		local value = bv or av
		local mode = " "

		if(string.sub(ftype, 1, 5) == "list/") then
			if(not dump and k == "comment") then k = "#" end
			rc = rc .. show_list(av, bv, k, indent, dump)
		elseif(value) then
			if(dump) then mode = " "
			elseif(not av) then mode = "+" 
			elseif(not bv) then mode = "-" 
			elseif(av ~= bv) then mode = "|" end
	
			if(string.sub(ftype, 1, 5) == "file/") then
				rc = rc .. show_file(mode, ftype, k, value, indent, dump)
			else	
				rc = rc .. op(mode, indent, k, value)
			end
		end
	end
	return rc
end

--
-- Display the config/delta in a form that is useful to a person.
-- Note that this is not used to save config information, a more
-- basic (less pretty) output is used.
--
function show_config(a, b, master, indent, parent)
	indent = indent or 0
	local rc = ""

	-- first the fields
	if(parent and each_field(master)()) then
		rc = rc .. op(" ", indent, parent, "(settings) {")
				.. show_fields(a, b, master, indent+4)
				.. op(" ", indent, "}")
	else
		rc = rc .. show_fields(a, b, master, indent)
	end

	-- now the containters
	for k in each_container(a, b, master) do
		local mode = " "
		local av = a and a[k]
		local bv = b and b[k]
		local mt = master and (master[k] or master["*"])

		if(av and not bv) then mode = "-" end
		if(bv and not av) then mode = "+" end

		local label = (mt._label or "") .. k

		if(mt._keep_with_children) then
			rc = rc .. show_config(av, bv, mt, indent, k)
		else
			rc = rc .. op(mode, indent, label, "{")
					.. show_config(av, bv, mt, indent+4)
					.. op(mode, indent, "}")
		end
::continue::
	end
	return rc
end

--
-- We need to be able to save/restore given configs, so we have
-- a basic function that dumps a single table in a format which
-- is human and machine readable.
--
-- The show_fields function has a dump flag which outputs in
-- a slightly different format.
--
function dump_config(a, master, indent)
	indent = indent or 0
	local rc = ""
	
	-- first the fields
	rc = rc .. show_fields(a, nil, master, indent, true)

	-- now the containers
	for k in each_container(a, nil, master) do
		local mt = master and (master[k] or master["*"])
		rc = rc .. op(" ", indent, k, "{")
				.. dump_config(a[k], mt, indent+4)
				.. op(" ", indent, "}")
	end
	return rc
end

--
-- We need to be able to load a config back in from a file
-- containing a dump.
--
function read_config(filename, master, file)
	local rc = {}
	local line

	-- file is internal, for our recursion
	if(not file) then
		file = io.open(filename)
		-- TODO: handle errors
	end

	while(true) do
		line = file:read()
		if(not line) then break end
	
		-- skip empty lines
		if(string.match(line, "^%s*$")) then goto continue end

		-- a close bracket if a recursion return, so exit loop
		if(string.match(line, "}$")) then break end

		-- look for a section start
		local sec = string.match(line, "^%s*([^%s]+)%s+{$")
		if(sec) then
			local mc = master and (master[sec] or master["*"])
			local ac

			-- read a new section, but only fill in if master is valid
			ac = read_config(nil, mc, file)
			if(mc) then rc[sec] = ac end
		else
			-- this should be a field...
			local key, value = string.match(line, "^%s*([^%s]+)%s+(.*)$")
			if(not key) then
				print("FIELD ERROR: " .. line)
			else
				local mc = master and master[key]
				local is_list = mc and mc._type and string.sub(mc._type, 1, 5) == "list/"
				local is_file = mc and mc._type and string.sub(mc._type, 1, 5) == "file/"

				if(is_list) then
					if(not rc[key]) then rc[key] = {} end
					table.insert(rc[key], value)
				elseif(is_file) then
					local data = ""

					while(1) do
						local line = file:read()
						if(mc._type == "file/binary") then
							line = string.gsub(line, "^%s+", "")
							data = data .. line
							if(string.match(line, "==$")) then
								rc[key] = dec(data)
								break
							end
						elseif(mc._type == "file/text") then
							if(string.match(line, "^%s+<eof>$")) then
								rc[key] = data
								break
							end
							line = string.gsub(line, "^%s+|", "")
							if(#data > 0) then data = data .. "\n" end
							data = data .. line
						end
					end
				elseif(mc) then
					rc[key] = value
				end
			end
		end
::continue::
	end

	-- close the file if we are the top level
	if(filename) then file:close() end

	return rc
end

--
-- We do any post processing of the master table so we remove the need
-- to do complex processing later on.
--
-- 1. Build the order field
-- 2. Create the _label options
--
function prepare_master(m, parent_name)
	--
	-- make sure we have a definition for comment in every node
	--
	if(not m["comment"]) then
		m["comment"] = { _type = "list/string", _no_exec = 1 }
	end

	--
	-- now build a list of what we have in this node, and recurse
	-- at the same time...
	--
	local fields = {}
	local containers = {}

	for k,mv in pairs(m) do
		if(string.sub(k, 1, 1) == "_") then goto continue end

		if(mv._type) then table.insert(fields, k)
		else table.insert(containers, k) end

		-- we need to recurse for any containers...
		if(not mv._type) then prepare_master(mv, k) end

		-- create the label if we are keeping with children
		if(m._keep_with_children) then mv._label = parent_name .. " " end
::continue::
	end

	--
	-- now prepare the _fields and _containers ordered lists
	--
	table.sort(fields)
	table.sort(containers)
	local order = m._order or {}
	local flist = {}
	local clist = {}

	if(not is_in_list(order, "comment")) then table.insert(order, 1, "comment") end

	for _,k in ipairs(order) do
		if(is_in_list(fields, k)) then 
			table.insert(flist, k)
			remove_from_list(fields, k)
		elseif(is_in_list(containers, k)) then
			table.insert(clist, k)
			remove_from_list(containers, k)
		end
	end
	append_list(flist, fields)
	append_list(clist, containers)

	m._fields = flist
	m._containers = clist
	m._order = nil
end


prepare_master(master)
print(show_config(two, one, master))
--print(dump_config(one, master))

--x = read_config("sample", master)
--print(dump_config(x, master))

a = { "one", "two", "three", { x=1, y=2 } }
b = { "one", "two", "three", { y=2, x=1 } }
--b = { "six", "two", "eight", "three" }
--a = {} 

--list_compare(a, b)

print(tostring(are_the_same(a, b)))


