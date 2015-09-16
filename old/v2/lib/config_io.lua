--------------------------------------------------------------------------------
--  This file is part of OpenTik.
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


-- ==============================================================================
-- ==============================================================================
--
-- These are the functions that support show_config, a means of both displaying
-- and serialising the configuration.
--
-- In "show" was also support highlighting of delta's using +, - and | 
--
-- ==============================================================================
-- ==============================================================================


--
-- UTILITY FUNCTIONS MOVE!
--
function copy_table(table)
	local rc = {}
	for k,v in pairs(table) do
		if(type(v) == "table") then
			rc[k] = copy_table(v)
		else
			rc[k] = v
		end
	end
	return rc
end
function is_in_list(list, item)
	for _,v in ipairs(list) do
		if(v == item) then return true end
	end
	return false
end
function remove_from_list(list, item)
	local p = 0
	for i = 1,#list do
		if(list[i] == item) then 
			p = i 
			break 
		end
	end
	if(p) then
		table.remove(list, p)
	end
	return p
end

--
-- See if the given node has children (master)
--
local function has_children(master)
	for k,v in pairs(master) do
		if(string.sub(k, 1, 1) ~= "_") then return true end
	end
	return false
end

--
-- Actually show the specific field
--
local function show_item(operation, indent, key, value)
	return operation .. string.rep(" ", indent) .. key .. " " .. value .. "\n"
end

--
-- Handle the displaying of lists, if we are added or removed in entirety
-- then we don't really care too much. If we are changed then we need to
-- show individual item add and removes.
--
local function show_list(ac, operation, indent, key, value)
	local op = ""

	--
	-- first we deal with the simple case of all add, all remove, or all same
	--
	if(operation ~= "|") then
		for _,v in ipairs(value) do
			op = op .. show_item(operation, indent, key, v)
		end
		return op
	end

	--
	-- We show the original list, with any removes highlighted as removes. Each
	-- remove must only operate once, so we remove them from the copy of the removes
	-- list
	--
	local dels = (value._items_deleted and copy_table(value._items_deleted)) or {}
	for _,v in ipairs(ac) do
		if(is_in_list(dels, v)) then
			operation = "-"
			remove_from_list(dels, v)
		else
			operation = " "
		end
		op = op .. show_item(operation, indent, key, v)
	end
	--
	-- Now we show any adds
	--
	local adds = value._items_added or {}
	for _,v in ipairs(adds) do
		op = op .. show_item("+", indent, key, v)
	end

	return op

end

--
-- Display a given field with the appropriate operation symbol
--
local function show_field(ac, dc, mc, k, indent, mode)
	local operation, value
	local op = ""
		print("Key is "..k)

	if(mode == "+" or (dc and dc._fields_added and dc._fields_added[k])) then
		operation = "+"
		value = dc and dc[k]
	elseif(mode == "-" or (dc and dc._fields_deleted and dc._fields_deleted[k])) then
		operation = "-"
		value = ac and ac[k]
	elseif(dc and dc._fields_changed and dc._fields_changed[k]) then
		operation = "|"
		value = dc and dc[k]
	else
		operation = " "
		value = ac and ac[k]
	end
	if(value) then
		-- comments are actually lists, so we just change the key
		if(k == "comment") then k = "#" end

		-- if we are a table then just show each item
		if(type(value) == "table") then
			op = op .. show_list(ac and ac[k], operation, indent, k, value)
		else
			op = op .. show_item(operation, indent, k, value)
		end
	end
	return op
end

--
-- Handle the labels on a node, and recurse if needed
--
local function show_node(ac, dc, mc, label, indent, mode, k)
	local parent = nil
	local has_wildcards = mc["*"]

	if(has_wildcards) then
		return show_config(ac, dc, mc, indent, mode, k)
	else
		return mode .. string.rep(" ", indent) .. label .. " {" .. "\n" ..
				show_config(ac, dc, mc, indent+4, mode, nil) ..
					mode .. string.rep(" ", indent) .. "}" .. "\n"
	end
end

--
-- Pull out all the relevant keys from active, delta and master
-- and then sort them, either based on master._order or just
-- put comments first and then the rest alphabetically
--
local function ordered_fields(active, delta, master)
	--
	-- first build the complete list...
	--
	local keys = {}
	if(active) then for k,_ in pairs(active) do keys[k] = 1 end end
	if(delta) then for k,_ in pairs(delta) do keys[k] = 1 end end
	if(master) then for k,_ in pairs(master) do keys[k] = 1 end end
	--
	-- now start populating the results... comment first, then
	-- based on master.order...
	--
	local klist = {}
	if(keys["comment"]) then
		table.insert(klist, "comment")
		keys["comment"] = nil
	end
	if(master and master._order) then
		for _,k in ipairs(master._order) do
			if(keys[k]) then
				table.insert(klist, k)
				keys[k] = nil
			end
		end
	end
	--
	-- now we build a list of the rest (removing directives), sort
	-- it, and then finish...
	--
	local left = {}
	for k,_ in pairs(keys) do
		if(string.sub(k, 1, 1) ~= "_") then
			table.insert(left, k)
		end
	end
	table.sort(left)
	for _,k in ipairs(left) do table.insert(klist, k) end
	return klist
end

--
-- Show the config in a human and machine readable form
--
function show_config(active, delta, master, indent, pmode, parent)
	local op = ""
	-- 
	-- setup some sensible defaults
	--
	indent = indent or 0

	--
	-- build a combined list of keys from active and delta
	-- so we catch the adds. We also takes the keys from
	-- master so we can catch field level stuff.
	-- 
	for _,k in ipairs(ordered_fields(active, delta, master)) do
		-- we don't want the wildcard key
		if(k == "*") then goto continue end

		-- inherit parent mode if set
		mode = pmode or " "

		-- is this a field to show
		local mc = master and (master[k] or master["*"])

		-- comments are a special case since they don't have a master
		-- record
		if(k == "comment") then
			op = op .. show_field(active, delta, master, k, indent, mode)
		end

		-- if we don't have a master then we don't do anything
		if(not mc) then goto continue end

		-- are we a field?
		if(not has_children(mc)) then
			op = op .. show_field(active, delta, master, k, indent, mode)
			goto continue
		end

		local ac = active and active[k]
		local dc = delta and delta[k]

		-- if we got a parent name passed down then we need
		-- to alter the way we show our name
		local label = k
		if(parent) then
			label = parent .. " " .. k
		end

		-- check for whole node deletes
		if(mode == "-" or (dc and dc._deleted)) then
			op = op .. show_node(ac, dc, mc, label, indent, "-", k)
			if(not (dc and dc._added)) then goto continue end
		end

		-- if we are adding then force mode
		if(dc and dc._added) then mode = "+" end

		-- now recurse for normal or added nodes
		op = op .. show_node(ac, dc, mc, label, indent, mode, k)

::continue::
	end
	return op
end

--
-- Read in a file in "config" format and convert it back into a
-- table
--
function read_config(filename, master, file)
	local rc = {}
	local line
	--
	-- we are going to recurse, so if the file isn't open then
	-- we need to open it here
	--
	if(not file) then
		file = io.open(filename)
		-- TODO: handle errors
	end
	while(true) do
		line = file:read();
		if(not line) then break end

		--
		-- we expect either a field value or a line with a "{" on it
		-- which means we are opening a new section, we can have one
		-- or two names depending if we have wildcard children
		-- if we get a close bracket, then we return (closing the file
		-- if we are the top level)
		--

		-- skip empty lines
		if(string.match(line, "^%s*$")) then goto continue end

		--
		-- if we get a close bracket then we need to return, so exit
		-- the loop
		--
		if(string.match(line, "}$")) then break end

		--
		-- look for a section start
		--
		local sec, sub = string.match(line, "^%s*([^%s]+)%s+([^%s]+)%s+{$")
		if(not sec) then
			sec = string.match(line, "^%s*([^%s]+)%s+{$")
		end
		if(sec) then
			local mc = master and master[sec]
			local ac
			--
			-- we have a section start, but we only fill in the return
			-- if we had an equivalent master to follow
			--
			if(sub) then
				mc = mc and (mc[sub] or mc["*"])
				ac = read_config(nil, mc, file)
				if(mc) then
					if(not rc[sec]) then rc[sec] = {} end
					rc[sec][sub] = ac
				end
			else
				ac = read_config(nil, mc, file)
				if(mc) then rc[sec] = ac end
			end
		else
			--
			-- this should be a field
			--
			local key, value = string.match(line, "^%s*([^%s]+)%s+(.*)$")
			if(not key) then
				print("FIELD ERROR: " .. line)
			else
				if(key == "#") then key = "comment" end
				local mc = master and master[key]
				local is_list = mc and mc._type and string.sub(mc._type, 1, 5) == "list/"

				if(is_list or key == "comment") then
					if(not rc[key]) then rc[key] = {} end
					table.insert(rc[key], value)
				elseif(mc) then
					rc[key] = value
				end
			end	
			
		end
::continue::
	end

	--
	-- close the file, if we are the top level
	--
	if(filename) then file:close() end
	return rc
end

