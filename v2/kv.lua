#!./luajit

--
-- Key/Value pair implementation using slashes
--
--
--

package.path = "./lib/?.lua"
package.cpath = "./lib/?.so"

-- different namespace packages
local base64 = require("base64")


local master={}
local current={}
local new={}

function callme()
	print("Hello")
end

function other()
	print("Other Hello")
end

function iptables()
	print("IPTAB")
end

--
-- Create a copy of the key/value list (or table)
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
-- Return the uniq sorted valies from a table (or two)
--
function sorted_values(kv1, kv2)
	local list = {}
	local uniq = {}

	if kv1 ~= nil then for _,v in pairs(kv1) do uniq[v] = 1 end end
	if kv2 ~= nil then for _,v in pairs(kv2) do uniq[v] = 1 end end
	for k,_ in pairs(uniq) do table.insert(list, k) end
	table.sort(list)
	return list
end

--
-- Return the uniq sorted keys from a table (or two)
--
function sorted_keys(kv1, kv2)
	local list = {}
	local uniq = {}

	if kv1 ~= nil then for k,_ in pairs(kv1) do uniq[k] = 1 end end
	if kv2 ~= nil then for k,_ in pairs(kv2) do uniq[k] = 1 end end
	for k,_ in pairs(uniq) do table.insert(list, k) end
	table.sort(list)
	return list
end

--
-- Find a given element within a list
--
function is_in_list(list, item)
	for _,k in ipairs(list) do
		if k == item then return true end
	end
	return false
end

--
-- Remove all elements that start with the prefix and return them in a list
--
function remove_prefixed(list, prefix)
	local plen = prefix:len()
	local rc = {}

	local i = 1
	while(i <= #list) do
		if list[i]:sub(1, plen) == prefix then
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

--
-- Given a master key, work back through the elements until we find one with
-- a function, then return that key.
--
function find_master_function(wk) 
	while wk:len() > 0 do
		print("Looking at ["..wk.."]")
		wk = wk:gsub("/?[^/]+$", "")
		if master[wk] and master[wk]["function"] then
			return wk
		end
	end
	return nil
end

--
--
--
--
function build_work_list()
	local rc = {}
	local sorted = sorted_keys(new, current)

	while #sorted > 0 do
		print("Finding work " .. #sorted)
		local key = sorted[1]

		print("Key is "..key)
		if new[key] ~= current[key] then
			print("We have work for: " .. key)
			local mkey = find_master_key(key)

			print("mkey="..tostring(mkey))
			local fkey = find_master_function(mkey)
			print("mkey="..tostring(mkey).." fkey="..tostring(fkey))
			if fkey then
				rc[fkey] = remove_prefixed(sorted, fkey)
			else
				print("No function found for " .. key)
			end
		else
			print("No work to do for " .. key)
			table.remove(sorted, 1)
		end
	end
	return rc
end

--
-- To action the new config we run through the master and find any nodes that have
-- a function.
--
-- If we find a function we can then look for all children and see if we have any changes
-- between current and new.
--
-- If there are changes then we can call the function
--
--
--





master["interface/ethernet"] = { ["function"] = callme,
								 ["depends"] = { "iptables" },
								 ["with_children"] = 1 }
master["interface/ethernet/*"] = { ["style"] = "ipv4" }
master["interface/ethernet/*/ip"] = { ["type"] = "ipv4" }
master["interface/ethernet/*/mtu"] = { ["type"] = "mtu" }

master["test"] = { ["function"] = other }
master["test/lee"] = { ["type"] = "name" }

master["iptables"] = { ["function"] = iptables }
master["iptables/*"] = { ["style"] = "iptables_primary" }
master["iptables/*/*"] = { ["style"] = "iptables_chain" }
master["iptables/*/*/policy"] = { ["type"] = "iptables_policy" }
master["iptables/*/*/rule"] = { 	["with_children"] = 1 }
master["iptables/*/*/rule/*"] = { 	["style"] = "iptables_rulenum", 
									["type"] = "iptables_rule",
									["quoted"] = 1 }

master["dns/forwarder/server"] = { ["type"] = "dns_forward", ["list"] = 1 }
master["dns/file"] = { ["type"] = "file/text" }


current["interface/ethernet/*0/ip"] = "192.168.95.1/24"
current["interface/ethernet/*1/ip"] = "192.168.95.2/24"
current["interface/ethernet/*0/mtu"] = 1500

current["dns/forwarder/server"] = { "one", "two", "three" }
current["dns/file"] = "afgljksdhfglkjsdhf glsjdfgsdfg\nsdfgkjsdfkljg\nsdfgsdg\nsdfgsdfg\n"


new = copy_table(current)
new["interface/ethernet/*1/ip"] = "192.168.95.4/24"
new["interface/ethernet/*2/ip"] = "192.168.95.33"
new["interface/ethernet/*0/mtu"] = nil

new["iptables/*filter/*FORWARD/policy"] = "ACCEPT"
new["iptables/*filter/*FORWARD/rule/*10"] = "-s 12.3.4 -j ACCEPT"
new["iptables/*filter/*FORWARD/rule/*20"] = "-d 2.3.4.5 -j DROP"

new["dns/forwarder/server"] = { "one", "three", "four" }

--x = find_master("interface/ethernet/*2/ip")
--print(tostring(x))

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
			if old_all[kp] == nil then
				disposition = "+"
			elseif new_all[kp] == nil then
				disposition = "-"
				value = old_all[kp]
			else
				disposition = "|"
			end
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
				if(not dump and i >= 76*3) then
					rc = rc .. op(disposition, indent+4, "... (total " .. #binary .. " bytes)")
					break
				end
			end
			if(dump) then rc = rc .. op(disposition, indent+4, "<eof>") end
		elseif(ftype == "text") then
			local lc = 0
			for line in (value .. "\n"):gmatch("(.-)\n") do
				rc = rc .. op(disposition, indent+4, "|"..line)
				if(not dump) then
					lc = lc + 1
					if(lc >= 4) then 
						rc = rc .. op(disposition, indent+4, "... <more>") 
						break
					end
				end
			end
			if(dump) then rc = rc .. op(mode, indent+4, "<eof>") end
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
			local disposition = " "
			if not is_in_list(old_list, value) then
				disposition = "+"
			elseif not is_in_list(new_list, value) then
				disposition = "-"
			end
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


show(current, new)


--[[
--
-- Build the work list
--
local work_list = build_work_list()

print("\n\n")
--
-- Now run through and check the dependencies
--
for key, fields in pairs(work_list) do
	print("Work: " .. key)
	for i,v in ipairs(fields) do
		print("\t" .. v)
	end

	local depends = master[key]["depends"] or {}
	for _,d in ipairs(depends) do
		print("\tDEPEND: " .. d)
		if work_list[d] then
			print("\tSKIP THIS ONE DUE TO DEPENDS")
			goto continue
		end
	end

	print("DOING WOEK\n")
	work_list[key] = nil
::continue::
end
]]--


