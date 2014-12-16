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
------------------------------------------------------------------------------

--
-- Globals for the validation routines
--
VALIDATOR = {}
FAIL=0
OK=1
PARTIAL=2

--
-- Remove all elements that start with the prefix and return them in a list
--
function remove_prefixed(list, prefix)
	local rc = {}

	local i = 1
	while(i <= #list) do
		if prefix_match(list[i], prefix, "/") then
			table.insert(rc, list[i])
			table.remove(list, i)
		else
			i = i + 1
		end
	end
	return rc
end


--
-- Find the master record for this entry. If we have any sections
-- starting the with * then it's a wildcard so we can remove the
-- following text to map directly to the wildcard master entry.
--
function find_master_key(k)
	--
	-- Revert back to just wildcards...
	--
	return k:gsub("/%*[^/]+", "/*")
end


--
-- Given a wildcard key (ending in a /*) return a list of the wildcards that are
-- mentioned within the provided kv table.
--
function node_list(wk, kv)
	local uniq = {}
	local rc = {}

	for k,_ in pairs(kv) do
		local wklen = wk:len()

		if(k:sub(1, wklen) == wk) then
			local elem = k:sub(wklen+1):gsub("/.*$", "")
			uniq[elem] = 1
		end
	end
	for k,_ in pairs(uniq) do table.insert(rc, k) end
	table.sort(rc)
	return rc
end
function node_exists(prefix, kv)
	for k,_ in pairs(kv) do
		if prefix_match(k, prefix, "/") then return true end
	end
	return false
end

--
-- Given a master key, work back through the elements until we find one with
-- a function, then return that key.
--
-- If we find a delegate instead of a function then we return the delegate
-- along with the location the delegate was found.
--
function find_master_function(wk) 
	while wk:len() > 0 do
		print("Looking at ["..wk.."]")
		wk = wk:gsub("/?[^/]+$", "")

		if master[wk] and master[wk]["function"] then
			return wk, wk
		end
		if master[wk] and master[wk]["delegate"] then
			return master[wk]["delegate"], wk
		end
	end

	return nil
end

--
--
--
--
function build_work_list(current, new)
	local rc = {}
	local sorted = sorted_keys(new, current)

	while #sorted > 0 do
		local key = sorted[1]

		if new[key] ~= current[key] then
			local mkey = find_master_key(key)

			local fkey, origkey = find_master_function(mkey)
			if fkey then
				if rc[fkey] == nil then rc[fkey] = {} end
				add_to_list(rc[fkey], remove_prefixed(sorted, origkey))
			else
				print("No function found for " .. key)
			end
		else
			table.remove(sorted, 1)
		end
	end
	return rc
end

--
-- Given a list of changes, pull out nodes at the keypath level
-- and work out if they are added, removed or changed.
--
-- NOTE: uses the global config variables
--
function process_changes(changes, keypath)
	local rc = { ["added"] = {}, ["removed"]= {}, ["changed"] = {} }

	local items = node_list(keypath, changes)
	for _,item in ipairs(items) do

		local in_old = next(node_list(keypath .. item, CF_current))
		local in_new = next(node_list(keypath .. item, CF_new))

		if in_old and in_new then table.insert(rc["changed"], item)
		elseif in_old then table.insert(rc["removed"], item)
		else table.insert(rc["added"], item) end
	end
	return rc
end


--
-- Return a hash containing a key for every node that is defined in
-- the original hash, values for end nodes, 1 for all others.
--
function hash_of_all_nodes(input)
	local rc = {}

	for k,v in pairs(input) do
		rc[k] = v
		while k:len() > 0 do
			k = k:gsub("/?[^/]+$", "")
			rc[k] = 1
		end
	end
	return rc
end

--
-- If we dump the config then we only write out the set items
--
function dump(config)
	for k,v in pairs(config) do
		local mc = master[find_master_key(k)] or {}

		if mc["list"] then
			io.write(string.format("%s: <list>\n", k))
			for _,l in ipairs(v) do
				io.write(string.format("\t|%s\n", l))
			end
			io.write("\t<end>\n")
		elseif mc["type"]:sub(1,5) == "file/" then
			io.write(string.format("%s: <%s>\n", k, mc["type"]))
			local ftype = mc["type"]:sub(6)
			if ftype == "binary" then
				local binary = base64.enc(v)
				for i=1, #binary, 76 do
					io.write(string.format("\t|%s\n", binary:sub(i, i+75)))
				end
			elseif ftype == "text" then
				for line in (v .. "\n"):gmatch("(.-)\n") do
					io.write(string.format("\t|%s\n", line))
				end
			end
			io.write("\t<end>\n")
		else 
			io.write(string.format("%s: %s\n", k, v))
		end
	end
end

--
-- Support re-loading the config from a dump file
--
function import(filename)
	local rc = {}
	local line, file

	function decode(data, ftype)
		if ftype == "file/binary" then
			return base64.dec(data)
		elseif ftype == "file/text" then
			return data
		else
			return nil
		end
	end

	file = io.open(filename)
	-- TODO: handle errors	
	
	while(true) do
		line = file:read()
		if not line then break end

		local kp, value = string.match(line, "^([^:]+): (.*)$")
		local mc = master[find_master_key(kp)] or {}
		local vtype = mc["type"]

		if mc["list"] then
			local list = {}
			while 1 do
				local line = file:read()
				if line:match("^%s+<end>$") then
					rc[kp] = list
					break
				end
				table.insert(list, (line:gsub("^%s+|", "")))
			end
		elseif vtype:sub(1,5) == "file/" then
			local data = ""
			while 1 do
				local line = file:read()
				if line:match("^%s+<end>$") then
					rc[kp] = decode(data, vtype)
					break
				end
				line = line:gsub("^%s+|", "")
				if vtype == "file/text" and #line > 0 then line = line .. "\n" end
				data = data .. line
			end
		else
			rc[kp] = value
		end
	end
	return rc
end

--
-- The main show function, using nested functions to keep the code
-- cleaner and more readable
--
function show(current, new, kp)
	kp = kp or ""

	--
	-- Build up a full list of nodes, and a combined list of all
	-- end nodes so we can process quickly
	--
	local old_all = hash_of_all_nodes(current)
	local new_all = hash_of_all_nodes(new)
	local combined = {}
	for k,_ in pairs(current) do combined[k] = 1 end	
	for k,_ in pairs(new) do combined[k] = 1 end	

	--
	-- Given a key path work out the disposition and correct
	-- value to show
	--
	function disposition_and_value(kp)
		local disposition = " "
		local value = new_all[kp]
		if old_all[kp] ~= new_all[kp] then
			disposition = (not old_all[kp] and "+") or (not new_all[kp] and "-") or "|"
			if disposition == "-" then value = old_all[kp] end
		end
		return disposition, value
	end


	--
	-- Handle the display of both dinay and text files
	--
	function display_file(mc, indent, parent, kp)
		local disposition, value = disposition_and_value(kp)

		local rc = ""
		local key = kp:gsub("^.*/%*?([^/]+)$", "%1")
		local ftype = mc["type"]:sub(6)

		function op(disposition, indent, label, value)
			local rhs = value and (label .. " " .. value) or label
			return string.format("%s %s%s\n", disposition, string.rep(" ", indent), rhs)
		end

		rc = op(disposition, indent, parent..key, "<"..ftype..">")
		if(ftype == "binary") then
			local binary = base64.enc(value)
			for i=1, #binary, 76 do
				rc = rc .. op(disposition, indent+4, binary:sub(i, i+75))
				if(i >= 76*3) then
					rc = rc .. op(disposition, indent+4, "... (total " .. #binary .. " bytes)")
					break
				end
			end
		elseif(ftype == "text") then
			local lc = 0
			for line in (value .. "\n"):gmatch("(.-)\n") do
				rc = rc .. op(disposition, indent+4, "|"..line)
				lc = lc + 1
				if(lc >= 4) then 
					rc = rc .. op(disposition, indent+4, "... <more>") 
					break
				end
			end
		end
		return rc
	end

	--
	-- Display a list field
	--
	function display_list(mc, indent, parent, kp)
		local rc = ""
		local key = kp:gsub("^.*/%*?([^/]+)$", "%1")
		local old_list, new_list = old_all[kp] or {}, new_all[kp] or {}
		local all_keys = sorted_values(old_list, new_list)

		for _,value in ipairs(all_keys) do
			local disposition = (not in_list(old_list, value) and "+") or 
										(not in_list(new_list, value) and "-") or " "

			if(mc["quoted"]) then value = "\"" .. value .. "\"" end
			rc = rc .. string.format("%s %s%s%s %s\n", disposition, 
							string.rep(" ", indent), parent, key, value)
		end
		return rc
	end

	--
	-- Display a value field, calling display_list if it's a list
	--
	function display_value(mc, indent, parent, kp)
		if(mc["list"]) then return display_list(mc, indent, parent, kp) end
		if(mc["type"]:sub(1,5) == "file/") then return display_file(mc, indent, parent, kp) end
	
		local disposition, value = disposition_and_value(kp)
		local key = kp:gsub("^.*/%*?([^/]+)$", "%1")
		if(mc["quoted"]) then value = "\"" .. value .. "\"" end
		return string.format("%s %s%s%s %s\n", disposition, 
						string.rep(" ", indent), parent, key, value)
	end

	--
	-- Display a container header or footer
	--
	function container_header_and_footer(indent, parent, kp)
		local disposition, value = disposition_and_value(kp)
		local key = kp:gsub("^.*/%*?([^/]+)$", "%1")
		local header = string.format("%s %s%s%s {\n", disposition, 
						string.rep(" ", indent), parent, key)
		local footer = string.format("%s %s}\n", disposition, string.rep(" ", indent))
	
		return header, footer
	end

	--
	-- Main recursive show function
	--
	function int_show(kp, combined, indent, parent)
		local indent = indent or 0
		local parent = parent or ""
		local indent_add = 4

		local nodes = node_list(kp, combined)
		for i,key in ipairs(nodes) do
			local dispkey = key:gsub("^%*", "")
			local newkp = kp .. key
			local mc = master[find_master_key(newkp)] or {}
			local disposition, value = disposition_and_value(newkp)

			if mc["type"] then
				--
				-- We are a field, so we can show our value...
				--
				io.write(display_value(mc, indent, parent, newkp))
			else
				--
				-- We must be a container
				--
				if mc["with_children"] then
					parent = parent .. dispkey .. " "
					int_show(newkp .. "/", combined, indent, parent)
				else
					local header, footer = container_header_and_footer(indent, parent, newkp)
					io.write(header)
					int_show(newkp .. "/", combined, indent+4)
					io.write(footer)
				end
			end
		end
	end	

	int_show(kp, combined)
end

--
-- Simple conditional join of strings
--
function join(v1, v2, joiner)
	return v1 .. ((#v1 > 0 and joiner) or "") .. v2
end

--
-- Find and execute a validator
--
function validate(vtype, kp, value)
	local validator = VALIDATOR[vtype]
	
	if not validator then return false, "undefined validator for "..vtype.." ["..value.."]" end
	local rc, err = validator(value, kp)

	if rc ~= OK then return false, "validation failed for "..vtype.." ["..value.."]: "..err end
	return true
end

--
-- Rework the provided path into the master structure, make sure any 
-- wildcards match the validators.
--
-- We return the real keypath (i.e. with *'s in front where needed)
--
function rework_kp(config, kp)
	local mp, rkp = "", ""

	while(1) do
		--
		-- Pull out each key in turn and work out if its a wildcard...
		--
		local k = kp:match("^([^/]+)/?")
		if not k then break end
		kp = kp:sub(#k + 2)

		--
		-- It's either a keypath or a wildcard path...
		--
		local master_kp = join(mp, k, "/")
		local master_wp = mp .. "/*"

		if master[master_wp] then
			--
			-- We are a wildcard key, so check we match style...
			--
			mp = master_wp
			rkp = join(rkp, "*"..k, "/")

			local rc, err = validate(master[mp]["style"], rkp, k)
			if not rc then return rc, err end
		elseif master[master_kp] then
			--
			-- We are a fixed key, so just build the path for now
			--
			mp = master_kp
			rkp = join(rkp, k, "/")
		else
			return false, "unknown configuration node: " .. master_kp
		end
	end
	return rkp
end

--
-- Convert and validate the provided path, then check the validator
-- for the type and then set the config.
--
function set(config, kp, value)
	local rkp, err = rework_kp(config, kp)
	if not rkp then return false, err end

	local mp = find_master_key(rkp)

	if master[mp]["type"] then
		local rc, err = validate(master[mp]["type"], rkp, value)
		if not rc then return false, err end
	else
		return false, "not a settable configuration node: "..rkp
	end
	--
	-- If we get here then we must be ok, add to list or set value
	-- accordingly
	--
	if master[mp]["list"] then
		if not config[rkp] then config[rkp] = {} end
		if not in_list(config[rkp], value) then
			table.insert(config[rkp], value)
		end
	else
		config[rkp] = value
	end
	return true
end

--
-- Rework the provided path and then delete anything that starts
-- with the same prefix (assuming there is something)
--
function delete(config, kp)
	local rkp, err = rework_kp(config, kp)
	if not rkp then return false, err end

	local count = 0
	for k,_ in pairs(config) do
		if prefix_match(k, rkp, "/") then
			config[k] = nil
		end
	end
end

