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
require("config_io")			-- allow reading and writing of configs

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
			resolvers = { "1.1.1.1", "2.2.2.2" },
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


