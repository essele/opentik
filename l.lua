#!./luajit

print("Hello")


local master

--
-- This is the main structural table, it defines how the various sections
-- operate and what dependencies exist
--
master = {
	["interface"] = {
		["ethernet"] = {
			["*"] = {
				_function = "handle_eth",
				_listmode = "system",
				_syntax = "handle_eth_syntax",
				["name"] = {
					_type = "string"
				},
				["address"] = {
					_type = "ipv4_net",
					_syntax = "handle_address_syntax",
				},
				["duplex"] = {
					_type = "ipv4_net",
				},
				["speed"] = {
					_function = "handle_speed",
				}
			}
		},
		["lo"] = {
		},
		["pppoe"] = {
			["*"] = {
				_function = "handle_pppoe",
				_listmode = "user"
			}
		},
	},
	["dns"] = {
		_depends = { "interface", "interface/ethernet/0" },
		_function = "handle_dnsmasq",
		_partners = { "dhcp" },
		["resolvers"] = {
			_type = "list/ipv4",
			_syntax = "syntax_ipv4",
		},
	},
	["dhcp"] = {
		_depends = { "interface/pppoe" },
		_function = "handle_dnsmasq",
		_partners = { "dns" }
	},
	["tinc"] = {
		_depends = { "interface", "dns" }
	}
}
	

local delta

delta = {
		["dns"] = {
			resolvers = { "8.8.8.8", "8.8.4.4" }
		},
		["interface"] = {
			["pppoe"] = {
				["0"] = {
					name = "pppoe0",
					master = "eth0",
					_depends = { "interface/ethernet/0" },
				}
			},
			["ethernet"] = {
				["0"] = {
					name = "eth0",
					address = "192.168.95.123/24",
					mtu = 1500,
					duplex = "auto",
					speed = "auto"
				},
				["1"] = {
					name = "eth1",
					address = "192.168.1.1/24"
				}
			},
		}
}

--
-- For a given path, return the relevant part of the delta and the
-- master
--
function get_tables(path, delta, master)
	local d = delta;
	local m = master;

	for key in string.gmatch(path, "([^/]+)") do
		local nodekey = key
		if(m and not m[nodekey] and m["*"]) then nodekey = "*" end

		if(d and d[key]) then d = d[key] else d = nil end
		if(m and m[nodekey]) then m = m[nodekey] else m = nil end
	end
	return d, m
end

--
-- Give a node path, see if it exists in the (delta) table, we use the get_tables
-- function to do this simply.
--
function node_exists(path, table)
	local d = get_tables(path, table, nil)

	return d ~= nil
end

--
-- Utility function to do useful array stuff
--
function append_array(a, b)
	for i, v in ipairs(b) do
		table.insert(a, v)
	end
end
function count_elements(hash)
	local rc = 0;
	for k,v in pairs(hash) do
		rc = rc + 1
	end
	return rc
end

--
-- Get the dependencies for a given path, we look at the master dependencies as
-- well as the ones in the deltas (dynamic)
--
function get_node_dependencies(path, delta, master)
	local d, m = get_tables(path, delta, master)
	local rc = {}

	if(m and m._depends) then append_array(rc, m._depends) end
	if(d and d._depends) then append_array(rc, d._depends) end
	return rc
end

--
-- For full dependencies we have to look at partners as well and keep recursing
-- until we have looked at everything
--
function get_full_dependencies(path, delta, master, hashref)
	local d, m = get_tables(path, delta, master)
	local rc = {}

	-- keep track of things we have dealt with...
	if(not hashref) then hashref = {} end

	rc = get_node_dependencies(path, delta, master)
	hashref[path] = 1;

	if(m and m._partners) then
		for i, p in ipairs(m._partners) do
			if(not hashref[p]) then
				append_array(rc, get_full_dependencies(p, delta, master, hashref))
			end
		end
	end
	return rc
end

--
-- We walk through the delta checking each node out, we look for dependencies
-- and skip any node where the dependencies are not complete.
--

function node_walk(path, dnode, mnode, full_deltas, full_master)
	local work_done = false

	--
	-- we want to process the keys in order, so we pull out the keys
	-- and then sort them
	--
	local keys = {}
	for k, v in pairs(dnode) do
		table.insert(keys, k)
	end
	table.sort(keys)

	--
	-- Now we can process the keys..
	--
	for i, k in ipairs(keys) do
		local v = dnode[k]
		local nodekey = k
		local npath = path .. "/" .. k

		if(not mnode[nodekey] and mnode["*"]) then nodekey = "*" end

		print("Looking at: " .. npath)

		--
		-- if we can't find the node in the master structure then it is
		-- an unknown node, we will just ignore it (and remove it from
		-- the dnode)
		if(mnode[nodekey] == nil) then
			print("Unknown node, ignoring: " .. nodekey)
			dnode[k] = nil
			goto continue
		end

		--
		-- At this point we have a valid node, we need to check if it's
		-- dependent on something, and see if we have covered that. If not
		-- we just skip it and will pick it up on the next run.
		--
		-- get_full_dependencies does a recursive look at partners as well
		-- so we will only show as ready to process once any partners are also
		-- ready to go
		--
		local depends = get_full_dependencies(npath, full_deltas, full_master)

		if(depends) then
			for i, d in ipairs(depends) do
				print("Dependency: "..d)
				if(node_exists(d, full_deltas)) then
					print("NODE NOT PROCESSED: "..d)
					goto continue
				end
			end
		end

		--
		-- if the value is a table and it's not defined as a basic list,
		-- then we need to recurse to traverse fully into the structure
		--
		local nodetype = mnode[nodekey]._type
		local func = mnode[nodekey]._function
		local is_list = nodetype and string.sub(nodetype, 1, 5) == "list/"
		local is_leaf = type(v) ~= "table" or is_list

		--
		-- We call our function if we have one, so it will be processed
		-- before the children (you should replace the function if you
		-- really need to shoehorn something in)
		--
		if(func) then
			print("Calling: " .. npath .. "[" .. func .. "]")
			work_done = true;

			--
			-- Any function is responsible to dealing with any fields that don't
			-- have a custom function assigned, so once we have called our function
			-- we can delete the fields (children) that we have processed.
			--
			if(not is_leaf) then
				-- TODO: process the values (i.e. store them in the global config)
				for kk,vv in pairs(v) do
					if(not mnode[nodekey][kk] or not mnode[nodekey][kk]._function) then
						v[kk] = nil
					end
				end
			end
		end

		--
		-- if we have children then we need to recurse to process them, we need to
		-- keep track of work_done in here
		--
		if(not is_leaf) then
			if(node_walk(npath, v, mnode[nodekey], full_deltas, full_master)) then
				work_done = true
			end
		end

		-- TODO: process the values (i.e. store them in the global config)
		if(type(v) ~= "table" or is_list) then
			print("Basic key value pair path="..path.. " k="..k.." v="..tostring(v))
		end

		--
		-- At this point we should have fully processed this node, so we can
		-- remove it
		--
		dnode[k] = nil
::continue::
	end
	
	return work_done
end

--
-- We need to run through the node list multiple times, we should process something
-- each time through otherwise there is a problem.
--
function process_delta(delta, master)
	while(1) do
		if(not node_walk("", delta, master, delta, master)) then
			print("NO WORK DONE!")
			break
		end
		for k,v in pairs(delta) do
			print("Still have -- " .. k)
		end
		local a = count_elements(delta)
		print("A="..a)
		if(a == 0) then
			break
		end
	end
end


process_delta(delta, master)

--node_walk("", t, delta, delta, t)
--node_exists("fred/bill/joe", {})
--node_exists("blah", {})
--

--local d, m = get_tables("interface/ethernet/4", delta, t )

--print("D=" .. tostring(d))
--print("M=" .. tostring(m))


