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
-- Add the second list to the first (updating the first)
--
function add_to_list(l1, l2)
	for _,v in ipairs(l2) do
		table.insert(l1, v)
	end
end

--
-- Find a given element within a list
--
function in_list(list, item)
	for _,k in ipairs(list) do
		if k == item then return true end
	end
	return false
end

--
-- Check to see if the prefix of line matches token, but where
-- the next char is either eol or the sep
--
function prefix_match(line, token, sep)
	if line:sub(1, #token) == token then
		local c = line:sub(#token+1, #token+1)
		if c == "" or c == sep then return true end
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
		if prefix_match(list[i], prefix, "/") then
--		if list[i]:sub(1, plen) == prefix then
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
function build_work_list()
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




master["interface"] = {}
master["interface/ethernet"] = { ["function"] = callme,
								 ["depends"] = { "iptables" },
								 ["with_children"] = 1 }
master["interface/ethernet/*"] = { ["style"] = "ethernet_if" }
master["interface/ethernet/*/ip"] = { ["type"] = "ipv4" }
master["interface/ethernet/*/mtu"] = { ["type"] = "mtu" }

master["test"] = { ["function"] = other }
master["test/lee"] = { ["type"] = "name" }

master["iptables"] = { ["function"] = iptables }
master["iptables/*"] = { ["style"] = "iptables_table" }
master["iptables/*/*"] = { ["style"] = "iptables_chain" }
master["iptables/*/*/policy"] = { ["type"] = "iptables_policy" }
master["iptables/*/*/rule"] = { 	["with_children"] = 1 }
master["iptables/*/*/rule/*"] = { 	["style"] = "OK", 
									["type"] = "iptables_rule",
									["quoted"] = 1 }

master["dns"] = { ["function"] = "xxx" }

master["dns/forwarder"] = {}
master["dns/forwarder/server"] = { ["type"] = "OK", ["list"] = 1 }
master["dns/file"] = { ["type"] = "file/text" }

master["dhcp"] = { 	["delegate"] = "dns" }
master["dhcp/flag"] = { ["type"] = "string" }

VALIDATOR = {}

FAIL=0
OK=1
PARTIAL=2


--
-- For ethernet interfaces we expect a simple number, but it needs
-- to map to a real interface (or be a virtual)
--
VALIDATOR["ethernet_if"] = function(v)
	--
	-- TODO: once we know the numbers are ok, we need to test for a real
	--       interface.
	--
	local err = "interface numbers should be [nnn] or [nnn:nnn] only"
	if v:match("^%d+$") then return OK end
	if v:match("^%d+:$") then return PARTIAL, err end
	if v:match("^%d+:%d+$") then return OK end
	return FAIL, err
end

VALIDATOR["mtu"] = function(v)
	--
	-- TODO: check the proper range of MTU numbers, may need to support
	--       jumbo frames
	--
	if not v:match("^%d+$") then return FAIL, "mtu must be numeric only" end
	local mtu = tonumber(v)

	if mtu < 100 then return PARTIAL, "mtu must be above 100" end
	if mtu > 1500 then return FAIL, "mtu must be 1500 or less" end
	return OK
end

VALIDATOR["iptables_table"] = function(v, kp)
	local valid = { ["filter"] = 1, ["mangle"] = 1, ["nat"] = 1, ["raw"] = 1 }

	if valid[v] then return OK end
	--
	-- Now check for partial...
	--
	for k,_ in pairs(valid) do
		if k:sub(1, #v) == v then return PARTIAL, "invalid table name" end
	end
	return FAIL, "invalid table name"
end

VALIDATOR["iptables_chain"] = function(v, kp)
	print("Validating chain ("..v..") for keypath ("..kp..")")
	return OK
end

VALIDATOR["iptables_rule"] = function(v, kp)
	print("Validating rule ("..v..") for keypath ("..kp..")")
	return OK
end

VALIDATOR["OK"] = function(v)
	return OK
end


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
--new["iptables2/*filter/*FORWARD/rule/*20"] = "-d 2.3.4.5 -j DROP"

new["dns/forwarder/server"] = { "one", "three", "four" }
new["dhcp/flag"] = "hello"

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

rc, err = set(new, "interface/ethernet/0/mtu", "1234")
if not rc then print("ERROR: " .. err) end
rc, err = set(new, "iptables/filter/INPUT/rule/0030", "-a -b -c")
if not rc then print("ERROR: " .. err) end
rc, err = set(new, "dns/forwarder/server", "a new one")
if not rc then print("ERROR: " .. err) end

delete(new, "iptables")

show(current, new)
--dump(new)
--local xx = import("sample")

--show(xx, xx)

--
-- Build the work list
--
work_list = build_work_list()

--print("\n\n")
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

