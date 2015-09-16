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

-- global level packages
require("lfs")
require("table_utils")
require("api")

-- different namespace packages
local base64 = require("base64")

--
-- Setup the base config structure
--
CONFIG = {}
CONFIG.master = {}
CONFIG.delta = {}
CONFIG.active = {}

--
-- And the validators
--
VALIDATOR = {}

--
-- We look at all of the module files and load each one which should
-- populate the master table and provide the required types, syntax
-- checkers and validators
--
-- We build a list of modules (*.mod) and the sort them and then dofile
-- them.
--
local modules = {}
for m in lfs.dir("modules") do
	if(string.match(m, "^.*%.mod$")) then
		table.insert(modules, m)
	end
end
table.sort(modules)

for i, m in ipairs(modules) do
	print("Loading: " .. m)
	dofile("modules/" .. m)
end


--
-- Basic lua functions for showing differences between two tables
--

--[[
CONFIG.master["dns"] = { _alias = "/dnsmasq/dns" }
CONFIG.master["dhcp"] = { _alias = "/dnsmasq/dhcp" }
CONFIG.master["dnsmasq"] = {
		_hidden = 1,
		_function = function() print("FCALL") end,
		["dns"] = {
			["resolvers"] = {
				_type = "list/ipv4"
			},
			["billy"] = {
				_type = "file/binary"
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
			["blah"] = { _type = "xx" },
			["blah2"] = { _type = "xy" }
		},
	}
CONFIG.master["lee"] = {
		_depends = { "/dnsmasq" },
		_function = function() print("Hello") end,
		["X"] = { _type = "xx" }
	}
]]--
CONFIG.active = {
--	["Xdns"] = { STUB = 1 },
--	["dhcp"] = { STUB = 1 },
--[[
	["dnsmasq"] = {
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
		},
	},
]]--
	["lee"] = {
		["X"]= 1
	}
}

--
-- standard formatting for show and dump is "[mode] [indent][label] [value]"
--
function op(mode, indent, label, value)
	local rh = (value and (label .. " " .. value)) or label
	
	return mode .. string.rep(" ", indent+1) .. rh .. "\n"
end

--
-- make path will create the structure to support the given path (if it
-- doesn't already exist)
--
function make_path(path, t)
	for key in string.gmatch(path, "([^/]+)") do
		if(not t[key]) then t[key] = {} end
		t = t[key]
	end
	return t
end

--
-- get nodes will find the given node in all three configs
-- it supports wildcards and aliases
--
function get_nodes(path, a, b)
	local mc = CONFIG.master
	a = a or CONFIG.active
	b = b or CONFIG.delta

	for key in string.gmatch(path, "([^/]+)") do
		mc = mc and (mc[key] or mc["*"])		-- support wildcards
		if(not mc) then return end

		if(mc._alias) then						-- support aliases
			mc, a, b = get_nodes(mc._alias)
		else
			a = a and a[key]
			b = b and b[key]
		end
	end
	return mc, a, b
end
function get_parent_nodes(path, a, b)
	local parent, key = string.match(path, "^(.*)/([^/]+)$")
	local mc, a, b = get_nodes(parent, a, b)
	return mc, key, a, b
end

--
-- If we have an alias in the path then our real path is different
--
function get_real_path(path)
	local mc = CONFIG.master
	local rc = path
	local cwd = ""
	local stub

	if(path == "/") then return "/" end

	while(#path > 0) do
		local key = path:match("^/?([^/]+)")
		path = path:gsub("^/([^/]+)", "")
		cwd = cwd .. "/" .. key

		mc = mc and (mc[key] or mc["*"])
		if(not mc) then return nil end

		if(mc._alias) then
			stub = cwd
			rc = mc._alias .. path
			mc = get_nodes(mc._alias)
		end
	end
	return rc, stub
end

--
-- given a path, separate out into the parent and node
--
function parent_and_node(path, t)
	local parent, node = string.match(path, "^(.*)/([^/]+)$")
	return parent, node
end

--
-- find any aliases that are contained within the specified
-- path child structure.
--
function each_contained_alias(path, mc, aliases)
	-- initialise if path is set
	if(path) then
		aliases = {}
		-- use parent and key otherwise we will follow the link
		mc,key = get_parent_nodes(path)
		mc = mc and (mc[key] or mc["*"])
	end

	-- the main check and recurse bit
	if(mc._alias) then 
		aliases[mc._alias] = 1
	else 
		for _,k in pairs(mc._containers) do
			each_contained_alias(nil, mc[k], aliases)
		end
	end

	-- return the iterator function
	if(path) then
		local last
		return function()
			last = next(aliases, last)
			return last
		end
	end
end

--
-- delete just removes a whole chunk from a config
--
function delete_node(path)
	-- handle the "everything" case...
	if(path == "" or path == "/") then
		CONFIG.delta = {}
		return
	end

	-- if we contain aliases, then delete them too
	for alias in each_contained_alias(path) do
		delete_node(alias)
	end

	local _,key,dc = get_parent_nodes(path, CONFIG.delta)
	if(not dc) then
		print("PARENT PATH DOES NOT EXIST for: "..path)
		return 
	end

	dc[key] = nil

	-- remove any empty lists
	clean_table(CONFIG.delta)
end

--
-- revert will make the table look the same as the original, this
-- will involve either a delete, or a copy from orig.
--
function revert_node(path)
	-- handle the "everything" case...
	if(path == "" or path == "/") then
		CONFIG.delta = copy_table(CONFIG.active)
		return
	end

	-- if we contain aliases, then delete them too
	for alias in each_contained_alias(path) do
		revert_node(alias)
	end

	-- find the original, if not present then delete from delta
	local _,ac = get_nodes(path, CONFIG.active)
	if(not ac) then return delete_node(path) end

	-- now make sure we have the parent structure, and copy...
	local parent, node = parent_and_node(path)
	local p = make_path(parent, CONFIG.delta)
	p[node] = (type(ac) == "table" and copy_table(ac)) or ac

	-- remove any empty lists
	clean_table(CONFIG.delta)
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
	local wildcards, clist = {}, {}

	for k,_ in pairs(keys(a, b)) do 
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
	local added, removed = {}, {}
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
	ftype = ftype:sub(6)

	rc = rc .. op(mode, indent, k, "<" .. ftype .. ">")
	if(ftype == "binary") then
		local binary = base64.enc(value)
		for i=1, #binary, 76 do
			rc = rc .. op(mode, indent+4, binary:sub(i, i+75))
			if(not dump and i >= 76*3) then
				rc = rc .. op(mode, indent+4, "... (total " .. #binary .. " bytes)")
				break
			end
		end
		if(dump) then rc = rc .. op(mode, indent+4, "<eof>") end
	elseif(ftype == "text") then
		local lc = 0
		for line in (value .. "\n"):gmatch("(.-)\n") do
			rc = rc .. op(mode, indent+4, "|" .. line)
			if(not dump) then
				lc = lc + 1
				if(lc >= 4) then
					-- TODO: show how many lines total? maybe not.
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
-- Do we have any fields set to show?
--
function has_set_fields(a, b, master)
	for k in each_field(master) do
		if((a and a[k]) or (b and b[k])) then return true end
	end
	return false
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

		if(ftype:sub(1, 5) == "list/") then
			if(not dump and k == "comment") then k = "#" end
			rc = rc .. show_list(av, bv, k, indent, dump)
		elseif(value) then
			if(dump) then mode = " "
			elseif(not av) then mode = "+" 
			elseif(not bv) then mode = "-" 
			elseif(av ~= bv) then mode = "|" end
	
			if(ftype:sub(1, 5) == "file/") then
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
-- (a) and (b) are optional, they will default to active, delta.
--
function show_config(path, a, b, master, orig_a, orig_b, indent, parent)
	local rc = ""

	if(path) then
		-- optional passed variables
		a = a or CONFIG.active
		b = b or CONFIG.delta

		-- build our internal variables
		orig_a = orig_a or a
		orig_b = orig_b or b
		indent = indent or 0

		-- prepare the path
		master, a, b = get_nodes(path, a, b)
	end

	-- first the fields
	if(parent and has_set_fields(a, b, master)) then
		local mode = " "
		if(a and not b) then mode = "-" end
		if(b and not a) then mode = "+" end
		rc = rc .. op(mode, indent, parent, "(settings) {")
				.. show_fields(a, b, master, indent+4)
				.. op(mode, indent, "}")
	else
		rc = rc .. show_fields(a, b, master, indent)
	end

	-- now the containters
	for k in each_container(a, b, master) do
		local mode = " "
		local av = a and a[k]
		local bv = b and b[k]
		local mt = master and (master[k] or master["*"])

		if(mt._hidden) then goto continue end
		if(mt._alias) then mt, av, bv = get_nodes(mt._alias, orig_a, orig_b) end

		if(av and not bv) then mode = "-" end
		if(bv and not av) then mode = "+" end

		local label = (mt._label or "") .. k

		if(mt._keep_with_children) then
			rc = rc .. show_config(nil, av, bv, mt, orig_a, orig_b, indent, k)
		else
			rc = rc .. op(mode, indent, label, "{")
					.. show_config(nil, av, bv, mt, orig_a, orig_b, indent+4)
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
function dump_config(a, master, orig_a, indent)
	-- build our internal variables
	master = master or CONFIG.master
	orig_a = orig_a or a
	indent = indent or 0

	local rc = ""
	
	-- first the fields
	rc = rc .. show_fields(a, nil, master, indent, true)

	-- now the containers
	for k in each_container(a, nil, master) do
		local mt = master and (master[k] or master["*"])
		local av = a and a[k]

		if(mt._hidden) then goto continue end
		if(mt._alias) then 
			mt, av = get_nodes(mt._alias, orig_a) 
		end
		
		rc = rc .. op(" ", indent, k, "{")
				.. dump_config(av, mt, orig_a, indent+4)
				.. op(" ", indent, "}")
::continue::
	end
	return rc
end

--
-- We need to be able to load a config back in from a file
-- containing a dump.
--
function read_config(filename, master, file, aliases)
	local rc = {}
	local line

	-- file is internal, for our recursion
	if(not file) then
		master = CONFIG.master
		aliases = {}
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
			-- find our mc, and one to pass to recursion (cater for aliases)
			local mc = master and (master[sec] or master["*"])
			local mcc = (mc and mc._alias and get_nodes(mc._alias)) or mc

			-- read the new section
			local ac = read_config(nil, mcc, file, aliases)

			if(mc) then
				-- for aliases, create the stub and keep the data safe for later
				if(mc._alias) then
					aliases[mc._alias] = ac
					rc[sec] = { STUB = 1 }
				else
					rc[sec] = ac 
				end
			end
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
							if(string.match(line, "^%s+<eof>$")) then
								rc[key] = base64.dec(data)
								break
							end
							line = string.gsub(line, "^%s+", "")
						elseif(mc._type == "file/text") then
							if(string.match(line, "^%s+<eof>$")) then
								rc[key] = data
								break
							end
							line = string.gsub(line, "^%s+|", "")
							if(#data > 0) then data = data .. "\n" end
						end
						data = data .. line
					end
				elseif(mc) then
					rc[key] = value
				end
			end
		end
::continue::
	end

	-- if we are the top level, close the file and process any aliases
	if(filename) then 
		file:close() 

		for path,v in pairs(aliases) do
			local parent, node = parent_and_node(path)
			local ac = make_path(parent, rc)
			ac[node] = v
		end
	end

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
	m = m or CONFIG.master

	-- make sure we have a definition for comment in every node
	if(not m.comment) then m.comment = { _type = "list/string", _no_exec = 1 } end

	-- if we are an alias, then just return
	if(m._alias) then return end

	-- now build a list of what we have in this node, and recurse at the same time...
	local fields, containers = {}, {}

	for k,mv in pairs(m) do
		if(k:sub(1, 1) == "_") then goto continue end

		if(mv._type) then table.insert(fields, k)
		else table.insert(containers, k) end

		-- we need to recurse for any containers...
		if(not mv._type) then prepare_master(mv, k) end

		-- create the label if we are keeping with children
		if(m._keep_with_children) then mv._label = parent_name .. " " end
::continue::
	end

	-- now prepare the _fields and _containers ordered lists
	table.sort(fields)
	table.sort(containers)
	local order = m._order or {}
	local flist, clist = {}, {}

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

--
-- Here we set a set of field values for a given node, we do syntax
-- checking on the fields, and make sure the fields are valid, so this
-- change won't succeed unless everything is ok.
--
-- i.e. partial changes do not happen
--
function set_config(path, items)
	local stub

	-- first check the node is valid...
	local mc = get_nodes(path)
	if(not mc or mc._type) then
		print("INVALID PATH: " .. path)
		return false
	end

	-- now check each of the fields are valid
	for k,v in pairs(items) do
		local ftype = mc[k] and mc[k]._type

		if(not ftype) then
			print("FIELD INVALID: " .. k)
			return false
		end

		-- if we are a file then check we can open it
		if(ftype:sub(1,5) == "file/" and v) then
			local file = io.open(v)
			if(not file) then
				print("invalid file: " .. v)
				return false
			end
			file:close()
		end

		-- TODO: field validation
		if(not VALIDATOR[ftype]) then
			print("WARNING: no validator for type: " .. ftype)
		else
			local rc, rv, err = pcall(VALIDATOR[ftype], v)
			print("VALIDATOR "..ftype.." returned: rc="..tostring(rc) .. " rv=" .. tostring(rv) .. " err="..tostring(err))
		end
	end

	path, stub = get_real_path(path)		-- cope with aliases
	
	-- make sure we have supporting structure and
	-- create the node if needed
	local dc = make_path(path, CONFIG.delta)

	-- now we can set each field...
	for k,v in pairs(items) do
		local ftype = mc[k]._type

		-- if we are an empty string then remove (lists will be cleaned anyway)
		if(type(v) == "string" and v == "") then
			v = nil
		elseif(ftype:sub(1, 5) == "list/") then
			v = v[1] and copy_table(v)		-- v[1] removes empty lists
		elseif(ftype:sub(1, 5) == "file/") then
			local file = io.open(v)
			v = file:read("*a")
			file:close()
		end
		dc[k] = v
	end

	-- create the stub if we have an aliases node with some content
	if(stub and next(dc)) then
		local parent, node = parent_and_node(stub)
		local dca = make_path(parent, CONFIG.delta)
		dca[node] = { STUB = 1 }
	end

	-- remove any empty lists
	clean_table(CONFIG.delta)
end


function only_non_exec_diffs(ac, dc, mc)
	for k,v in pairs(mc) do
		local av = ac and ac[k]
		local dv = dc and dc[k]
		local mv = mc and (mc[k] or mc["*"])

		if(type(mv) == "table") then
			if(mv._type) then
				if(not are_the_same(av, dv) and not mv._no_exec) then return false end
			else
				if(not only_non_exec_diffs(av, dv, mv)) then return false end
			end
		end
	end
end

--
-- See if all of our dependencies are met, or if there are outstanding changes
-- to be applied
--
function dependencies_met(deplist)
	for _,dep in ipairs(deplist) do
		local mc, ac, dc = get_nodes(dep)
		
		print("Lookng at dep: " .. dep)
		if(not are_the_same(ac, dc)) then
			print("FAIL")
			return false
		end
	end
	return true
end

--
-- When we need to set the value, if we don't have a current
-- "ac" then we need to create the structure, or potential delete
-- it if we assign a nil
--
function set_active(ac, path, key, value)
	ac = ac or make_path(path, CONFIG.active)
	ac[key] = value
	if(not value) then clean_table(CONFIG.active) end
end

--
-- Committing th delta means dealing with normal changes, non-exec changes
-- and also the virtual nodes, so we'll walk the master tree so we can catch
-- virtual stuff, and anything that has been deleted
--
function commit_delta(ac, dc, mc, path)
	if(not path) then
		ac, dc, mc = CONFIG.active, CONFIG.delta, CONFIG.master
		path = ""
	end

	local work_done = false
	for k in pairs(keys(ac, dc, mc)) do
		if(k == "*" or k:sub(1,1) == "_") then goto continue end
		
		local av = ac and ac[k]
		local dv = dc and dc[k]
		local mv = mc and (mc[k] or mc["*"])

		-- we only want containers
		if(type(mv) ~= "table" or mv._type) then goto continue end

		-- we need active or delta to do anything
		if(not av and not dv) then goto continue end

		-- if we don't have any differences then there is nothing to do
		if(are_the_same(av, dv)) then goto continue end

		-- if we are an alias, then we must copy the state over
		if(mv._alias) then
			set_active(ac, path, k, dc[k])
			work_done = true
			goto continue
		end

		-- if the differences are only non-exec then we can just apply
		if(only_non_exec_diffs(av, dv, mv)) then
			print("NON EXEC DIFFS ONLY")
			set_active(ac, path, k, dc[k] and copy_table(dc[k]))
			work_done = true
			goto continue
		end

		-- we know we have diffs here now, if we have a function then exec
		if(mv._function) then
			print("DEPCHECK")
			if(mv._depends and not dependencies_met(mv._depends)) then
				print("DEPENDENCIES NOT MET, DEFERRING")
				goto continue
			end
			print("WOULD EXEC FOR: "..path .. "/" ..k)
			local rc, err = pcall(mv._function, path .. "/" .. k, k, { ac=av, dc=dv, mc=mv })
			if(not rc) then
				print("Call failed.")
				print("ERR: " .. err)
				-- TODO: errors
				return nil, err
			end

			set_active(ac, path, k, dc and dc[k] and copy_table(dc[k]))
			work_done = true
			goto continue
		end

		-- changes are present, but no function, so we need to recurse
		print("recursing for " .. path .. "/" .. k)
		local wd, err = commit_delta(av, dv, mv, path .. "/" .. k)
		if(wd == nil) then return wd, err end
		if(wd) then work_done = true end

::continue::
	end
	return work_done
end

--
-- The commit_delta function may need to be called multiple times to ensure
-- that dependencies are handled properly.
--
-- We should call it until we get no work done.
--
function commit()
	while(1) do
		print("CD")
		local wd, err = commit_delta()
		if(wd == nil) then
			print("ERROR, exiting")
			break;
		end
		if(not wd) then
			print("NO WORK DONE, exiting")
			break;
		end
	end
end



prepare_master()


CONFIG.delta = copy_table(CONFIG.active)

--revert_node("/dhcp/a/fred")
--delete_node("/dhcp")
--set_config("/dns/abc", { yes="HELLO", comment={ "", "new item", "" }})
--set_config("/dhcp", { blah = 1 })
--set_config("/dhcp/one", { fred = 45 })
--set_config("/lee", { X = 4567 })
--set_config("/interface/ethernet/0", { address = "1.2.3.4/24" })

set_config("/dns", { resolvers = { "1.2.3.4", "4.5.6.7" } } )
set_config("/dns/host/pbx", { ipv4 = "3.3.3.3", aliases = { "phone", "blah" }})
set_config("/dns/host/gate", { ipv4 = "4.4.4.4" })
set_config("/dns/host/joe", { ipv4 = "4.4.5.6" })

--set_config("X", { fred="" })
--
commit()
print(show_config("/"))

--delete_node("/interface/ethernet/0")
--dump(CONFIG.delta)
--commit()

--delete_node("/dns")
--commit_delta()

print("XXX")
--print(dump_config(CONFIG.active))
--dump(CONFIG.active)

--print(show_config(CONFIG.active, CONFIG.delta, CONFIG.master))
--print("=====")
--print(show_config(CONFIG.active, CONFIG.delta, CONFIG.master))
--dump(CONFIG.delta)

--x = read_config("sample")
--dump(x)
--print(dump_config(x))

--a = { "one", "two", "three", { x=1, y=2 } }
--b = { "one", "two", "three", { y=2, x=1 } }
--b = { "six", "two", "eight", "three" }
--a = {} 

--list_compare(a, b)

--print(tostring(are_the_same(a, b)))


