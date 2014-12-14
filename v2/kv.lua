#!./luajit

--
-- Key/Value pair implementation using slashes
--

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
-- Create a copy of the key/value list
--
function copy_kv(s)
	local rc = {}
	for k,v in pairs(s) do rc[k] = v end
	return rc
end

--
-- Return the sorted keys from a table (or two)
--
function sorted_keys(kv1, kv2)
	local list = {}
	local uniq = {}

	if kv1 ~= nil then
		for k,_ in pairs(kv1) do uniq[k] = 1 end
	end
	if kv2 ~= nil then
		for k,_ in pairs(kv2) do uniq[k] = 1 end
	end
	for k,_ in pairs(uniq) do table.insert(list, k) end
	table.sort(list)
	return list
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
	local wc = k:gsub("/%*[^/]+", "/*")
	--
	-- Now see if we have a match
	--
	return wc
	--return master[wc] or nil
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
master["iptables/*/*/*"] = { ["style"] = "iptables_rulenum", ["type"] = "iptables_rule" }


current["interface/ethernet/*0/ip"] = "192.168.95.1/24"
current["interface/ethernet/*1/ip"] = "192.168.95.2/24"
current["interface/ethernet/*0/mtu"] = 1500




new = copy_kv(current)
new["interface/ethernet/*2/ip"] = "192.168.95.33"
new["interface/ethernet/*0/mtu"] = 1498

new["iptables/*filter/*FORWARD/policy"] = "ACCEPT"
new["iptables/*filter/*FORWARD/*10"] = "-s 12.3.4 -j ACCEPT"
new["iptables/*filter/*FORWARD/*20"] = "-d 2.3.4.5 -j DROP"

--x = find_master("interface/ethernet/*2/ip")
--print(tostring(x))

rc = node_list("iptables/*", new)
for i,v in ipairs(rc) do
	print("i="..i.." v="..v)
end
rc = node_list("iptables/*filter/*FORWARD/*", new)
for i,v in ipairs(rc) do
	print("i="..i.." v="..v)
end

rc = node_list("", master)
for i,v in ipairs(rc) do
	print("i="..i.." v="..v)
end





--
-- To show the structure we build a combined hash so we can use node_list
-- recursively
--
local combined = {}
for k,_ in pairs(current) do combined[k] = 1 end	
for k,_ in pairs(new) do combined[k] = 1 end	

function show(sp, combined, indent, parent)
	local indent = indent or 0
	local parent = parent or ""
	local indent_add = 4

	local nodes = node_list(sp, combined)
	for i,key in ipairs(nodes) do
		local dispkey = key:gsub("^%*", "")
		local newsp = sp .. key .. "/"
		local mkey = find_master_key(sp .. key)

		if master[mkey] and master[mkey]["type"] then
			--
			-- We are a field, so we can show our value...
			--
			print(string.rep(" ", indent) .. parent .. dispkey .. " = (todo)")
		else
			--
			-- We must be a container
			--
			if master[mkey] and master[mkey]["with_children"] then
				parent = parent .. dispkey .. " "
				show(newsp, combined, indent, parent)
			else
				print(string.rep(" ", indent) .. parent .. dispkey .. " {")
				show(newsp, combined, indent+4)
				print(string.rep(" ", indent) .. "}")
			end
		end
	end
end	


show("", combined)


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


