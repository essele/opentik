#!./luajit

DO NOT USE ... see main.lua

package.cpath = "./libs/?.so"

require("lfs")

--
-- global: master
--
-- This is the main structural table, it defines how the various sections
-- operate and what dependencies exist
--
CONFIG = {}
CONFIG.master = {
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
	},
	["fred"] = {
		["*"] = {
			["value"] = {
				_type = "blah"
			}
		}
	},
	["test"] = {
		["test2"] = {
			["test3"] = {
				["test4"] = {
					["value"] = {
						_type = "blah"
					}
				}
			}
		}
	}
}

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
-- We have an "active" configuration, which is the live one, in use,
-- where previous commits have been made.
--
-- We have a "delta" which contains information that we have changed
-- (added, changed, deleted) which we need to process upon a commit
--
-- We can then build a "tobe" config which is the result of the
-- "active" when the "delta" have been applied
--
-- All of these configs are stored in the global CONFIG variable
--

CONFIG.active = {
		["dns"] = {
			resolvers = { "8.8.8.8", "8.8.4.4" }
		},
		["test"] = {
			["test2"] = {
				["test3"] = {
					["test4"] = {
						value = 77
					}
				}
			}
		},
		["interface"] = {
			["ethernet"] = {
				["0"] = {
					name = "eth0",
					address = "192.168.95.123/24",
					comment = {"this is a comment about this interface",
								"with two lines"}
				},
				["2"] = {
					name = "fred",
					address = "192.168.99.111/16"
				}
			}
		}
}

CONFIG.delta = {
		["dns"] = {
--			resolvers = { "1.1.1.1", "2.2.2.2" }
			resolvers = {
				_items_deleted = { "8.8.8.8", "8.8.4.4" },
				_items_added = { "1.1.1.1", "2.2.2.2" },
			 },
			_changed = 1,
			_fields_changed = { ["resolvers"] = 1 }
		},
		["fred"] = {
			["one"] = {
				value = "blah blah blah",
				_added = 1
			},
			["two"] = {
				value = "abc abc abc",
				_added = 1
			},
			["three"] = {
				value = "x y z",
				_added = 1
			}
		},
		["interface"] = {
			["pppoe"] = {
				["0"] = {
					name = "pppoe0",
					master = "eth0",
					_depends = { "interface/ethernet/0" },
					_added = 1
				},
			},
			["ethernet"] = {
				["0"] = {
					mtu = 1500,
					duplex = "auto",
					speed = "auto",
					_changed = 1,
					_fields_added = { ["mtu"] = 1, ["duplex"] = 1, ["speed"] = 1 },
					_fields_deleted = { ["grog"] = 1 }
				},
				["1"] = {
					name = "eth1",
					address = "192.168.1.1/24",
					_added = 1
				},

				--
				-- If we delete a node, then _deleted will be set, we can also add
				-- a node back, then _added will be set.
				--
				-- If we have added or removed fields, then _changed will be set
				-- along with _fields_added, _fields_changed, _fields_removed
				--
				["2"] = {
					_deleted = 1
				},
			},
		},
		["firewall"] = {
			["filter"] = {
				["chain"] = {
					["fred"] = {
						_added = 1,
						policy = "ACCEPT",
						["rule"] = {
							["10"] = {
								comment = {"blah"},
								_changed = 1,
								_fields_added = { ["comment"] = 1 }
							},
							["20"] = {
								_added = 1,
								target = "ACCEPT",
								match = "-m tcp -p tcp"
							}
						}
					}
				}
			}
		}
	
		--
		-- At the main node level we have a _status field which shows
		-- the disposition of the main node, either "added", "changed", or "deleted".
		--
		-- For "added" and "deleted" there are no sub definitions since all subfields
		-- are either new, or going.
		--
		-- For "changed" we will create three new hashes showing which fields have
		-- been added, deleted or changed.
		--
		-- TODO: how do we cope with deleted, then added?
		-- 		 could do it with a function that builds an action list in order
		-- 		 of nodes deleted, then changed, then added
		--
		-- Maybe better, we stick to three lists at each level and don't do the node
		-- specific stuff.
		--
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
-- For a given path, return the parent (which will allow us to delete
-- any sub nodes etc)...
--
function get_node(path, table)
	local t = table

	for key in string.gmatch(path, "([^/]+)") do
		if(t and t[key]) then t = t[key] else t = nil end
	end
	return t
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
-- In a delta we sometimes need to know if there is any valid content
-- (other than directives)
-- TODO: is this the same has has children?
--
function has_content(delta)
	for k,v in pairs(delta) do
		if(string.sub(k, 1, 1) ~= "_") then return true end
	end
	return false
end

--
-- For a set of hashes, pull out all of the unique (non directive)
-- keys and return a sorted array of them
--
function all_keys(...)
	local keys = {}
	local klist = {}
	for _,arr in ipairs({...}) do
		if(arr) then
			for k,_ in pairs(arr) do 
				if(string.sub(k, 1, 1) ~= "_") then keys[k] = 1 end
			end
		end
	end
	for k,_ in pairs(keys) do table.insert(klist, k) end
	table.sort(klist)
	return klist
end

--
-- Recursive processing of config changes, delta[key] must be a table
--
function apply_delta(table, delta, key)
	if(delta[key]._deleted) then
		print("Deleted key: " .. key)
		table[key] = nil
	end

	-- if delta[key] is a table and doesn't have any content we will return
	if(not has_content(delta[key])) then
		return
	end

	-- we know we have content now, so create the object if needed
	if(not table[key]) then
		table[key] = {}
		print("Prepared table: " .. key)
	end

	-- first we process any deleted fields
	if(delta[key]._fields_deleted) then
		for k, v in pairs(delta[key]._fields_deleted) do
			print("Deleting field: " ..k)
			table[key][k] = nil
		end
	end

	-- now handle the adds and changes (and recursion for tables)
	for k, v in pairs(delta[key]) do
		-- ignore all the directives...
		if(string.sub(k,1,1) == "_") then goto loop end

		if(type(v) == "table") then
			print("Recursing for: " ..k)
			apply_delta(table[key], delta[key], k)
		else
			print("Setting field: " ..k)
			table[key][k] = v
		end
::loop::
	end

	-- before we return we should check if we are empty, if so we can
	-- delete ourselves, just to keep the table tidy
	if(not has_content(table[key])) then
		table[key] = nil;
	end
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
function get_full_dependencies(path, hashref)
	local d, m = get_tables(path, delta, master)
	local rc = {}

	-- keep track of things we have dealt with...
	if(not hashref) then hashref = {} end

	rc = get_node_dependencies(path, CONFIG.delta, CONFIG.master)
	hashref[path] = 1;

	if(m and m._partners) then
		for i, p in ipairs(m._partners) do
			if(not hashref[p]) then
				append_array(rc, get_full_dependencies(p, hashref))
			end
		end
	end
	return rc
end

--
-- We walk through the delta checking each node out, we look for dependencies
-- and skip any node where the dependencies are not complete.
--

function node_walk(path, dnode, mnode)
	local work_done = false

	--
	-- we want to process the keys in order, so we pull out the keys
	-- and then sort them, for items that we are deleting we want
	-- them to be handled early (subject to dependencies) and if
	-- we are deleting and then adding we will need to call twice
	-- and we should only delete the first time round
	--
	local keys = {}
	for k, v in pairs(dnode) do
		if(string.sub(k, 1, 1) ~= "_") then
			if(dnode[k]._deleted) then
				table.insert(keys, "D "..k)
				if(dnode[k]._added) then
					table.insert(keys, "P "..k)
				end
			else
				table.insert(keys, "P "..k)
			end
		end
	end
	table.sort(keys)

	--
	-- Now we can process the keys..
	--
	for i, k in ipairs(keys) do
		print("KKKKKKKKKKKKKKK = "..k)
		-- remove the + or -
		k = string.sub(k, 3)

		-- work out our path, and go...
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
		local depends = get_full_dependencies(npath)

		if(depends) then
			for i, d in ipairs(depends) do
				print("Dependency: "..d)
				if(node_exists(d, CONFIG.delta)) then
					print("NODE NOT PROCESSED: "..d)
					goto continue
				end
			end
		end

		--
		-- if we have a function at this level, then we will call the
		-- function with the node and the master information so that 
		-- it can process any children.
		--
		-- If there is no function then we recurse
		--
		local nodetype = mnode[nodekey]._type
		local func = mnode[nodekey]._function
		local is_list = nodetype and string.sub(nodetype, 1, 5) == "list/"
		local is_leaf = type(v) ~= "table" or is_list

		-- we should never get to a leaf unless we've missed out
		-- a function definition in the master
		if(is_leaf) then error("LEAF!") end

		if(func and is_leaf) then
			error("leaf item with function definition")
		end

		if(func) then
			local rc, err

			print("Calling: " .. npath .. " [" .. tostring(func) .. "]")

			rc, err = pcall(func, npath, k, v, mnode[nodekey])
			if(not rc) then
				print("Call failed.")
				print("ERR: " .. err)
			end

			-- at this point we should have successfully commited this node
			-- so we need to update the active configuration, if we had a
			-- _deleted, then this operation will be a delete (only), we will
			-- be called again if we need to add
			
			local parent = get_node(path, CONFIG.active)
			print("Parent="..tostring(parent))

			if(v._deleted) then
				parent[k] = nil
				v._deleted = nil
			else
				apply_delta(parent, dnode, k)
				dnode[k] = nil;
			end
			work_done = true;
		else
			-- we should recurse, but only if we aren't a leaf...
			if(not is_leaf) then
				if(node_walk(npath, v, mnode[nodekey])) then
					work_done = true
				end
			end
		end
		-- tidy up if we are empty...
		print("PATH="..npath.."  leaf="..tostring(is_leaf))
		if(dnode[k] and not has_content(dnode[k])) then dnode[k] = nil end
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
-- See if the given node has children (master)
--
function has_children(master)
	for k,v in pairs(master) do
		if(string.sub(k, 1, 1) ~= "_") then return true end
	end
	return false
end

--
-- Actually show the specific field
--
function show_item(operation, indent, key, value)
	return operation .. string.rep(" ", indent) .. key .. " " .. value .. "\n"
end

--
-- Display a given field with the appropriate operation symbol
--
function show_field(ac, dc, mc, k, indent, mode)
	local operation, value
	local op = ""

	if(mode == "+" or (dc and dc._fields_added and dc._fields_added[k])) then
		operation = "+"
		value = dc[k]
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
			-- TODO: handle list adds/removes
			for _,v in ipairs(value) do
				op = op .. show_item(operation, indent, k, v)
			end
		else
			op = op .. show_item(operation, indent, k, value)
		end
	end
	return op
end

--
-- Handle the labels on a node, and recurse if needed
--
function show_node(ac, dc, mc, label, indent, mode, k)
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
function ordered_fields(active, delta, master)
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
function show_config(active, delta, master, indent, mode, parent)
	local op = ""
	-- 
	-- setup some sensible defaults
	--
	mode = mode or " "
	indent = indent or 0

	--
	-- build a combined list of keys from active and delta
	-- so we catch the adds. We also takes the keys from
	-- master so we can catch field level stuff.
	-- 
	for _,k in ipairs(ordered_fields(active, delta, master)) do
		-- we don't want the wildcard key
		if(k == "*") then goto continue end

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


--TODO -- fix the apply_delta to be based on master (might be easier)
--

cc = read_config("sample", CONFIG.master)
print(show_config(cc, nil, CONFIG.master))

--op = show_config(CONFIG.active, CONFIG.delta, CONFIG.master)
--op = show_config(CONFIG.active, nil, CONFIG.master)
--print(op)


--show_config(CONFIG.active, nil, CONFIG.master)
--process_delta(CONFIG.delta, CONFIG.master)

--apply_delta(CONFIG.active, CONFIG.delta, "interface")

--node_walk("", t, delta, delta, t)
--node_exists("fred/bill/joe", {})
--node_exists("blah", {})
--

--local d, m = get_tables("interface/ethernet/4", delta, t )

--print("D=" .. tostring(d))
--print("M=" .. tostring(m))


