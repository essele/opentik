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
			_function = function() return true end,
			["value"] = {
				_type = "blah"
			}
		}
	},
	["test"] = {
		["test2"] = {
			["test3"] = {
				["test4"] = {
					_function = function() return true end,
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
			resolvers = {
				_items_deleted = { "8.8.4.4" },
				_items_added = { "1.1.1.1", "2.2.2.2" },
			},
			_changed = 1,
			_fields_changed = { ["resolvers"] = 1 }
		},
		["test"] = {
--			_added = 1,
			["test2"] = {
--				_added = 1,
				["test3"] = {
--					_added = 1,
					["test4"] = {
						value = 77,
						_added = 1
					}
				}
			}
		},
		["fred"] = {
			_added = 1,
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
function get_tables(path, delta, master, active)
	local d = delta;
	local m = master;
	local a = active

	for key in string.gmatch(path, "([^/]+)") do
		m = m and (m[key] or m["*"])
		d = d and d[key]
		a = a and a[key]
	end
	return d, m, a
end

--
-- For a given path, return the node 
--
function get_node(path, table)
	local t = table

	for key in string.gmatch(path, "([^/]+)") do
		t = t and t[key]
		if(not t) then break end
	end
	return t
end
node_exists = get_node


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
		if(string.sub(k,1,1) == "_") then goto continue end

		if(type(v) == "table") then
			print("Recursing for: " ..k)
			apply_delta(table[key], delta[key], k)
		else
			print("Setting field: " ..k)
			table[key][k] = v
		end
::continue::
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
function get_full_dependencies(path, originals, hashref)
	local d, m = get_tables(path, originals.delta, originals.master)
	local rc = {}

	-- keep track of things we have dealt with...
	if(not hashref) then hashref = {} end

	rc = get_node_dependencies(path, originals.delta, originals.master)
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
-- For a given path, see if all the dependencies are met
--
function dependencies_met(path, originals)
	local deps = get_full_dependencies(path, originals)
	for _,d in ipairs(deps) do
		print("Checking dep: " .. d)
		if(get_node(d, originals.delta)) then return false end
	end
	return true
end


-- ==============================================================================
-- ==============================================================================
--
-- These functions support going through the delta and working out which functions
-- we need to call.
--
-- ==============================================================================
-- ==============================================================================


--
-- do we have child nodes?
--
function has_children(table)
	for k,v in pairs(table) do
		if(string.sub(k, 1, 1) ~= "_") then return true end
	end
	return false
end
function list_children(ctable)
	local rc = {}
	for k,v in pairs(ctable) do
		if(string.sub(k, 1, 1) ~= "_") then table.insert(rc, k) end
	end
	table.sort(rc)
	return rc
end

--
-- Walk the delta tree looking for changes that need to be processed
-- by a function. If we decide we need to call a function then we
-- check to see if any dependencies (and partner dependencies) are
-- met. That means that none of the dependencies are still showing
-- in the delta (i.e. have uncommitted changes)
--
function new_do_delta(delta, master, active, originals, path, key)
	--
	-- if we have a function and anything has changed then
	-- we will need to call it (if our dependencies are met)
	--
	local func = master._function
	local need_exec = false
	local work_done = false
	local clear_node = false

	-- prepare path by adding key (and initing when needed)
	path = path or ""
	if(key) then 
		path = path .. "/" .. key 
	end

	TODO: make active the parent, make sure we have populated the child
		  on the way in ... then delete on the way out if empty.

	-- look at the items we contain...
	for _,k in ipairs(list_children(delta)) do
		if(string.sub(k, 1, 1) == "_") then goto continue end

		-- work out the master for the item, just clear the key
		-- if we don't have one (i.e. the delta is garbage)
		local dc = delta[k]
		local mc = master[k] or master["*"]
		if(not mc) then 
			delta[k] = nil
			goto continue 
		end

		-- if we have children then we need to recurse further
		if(has_children(mc)) then
			local ne, wd, cn = new_do_delta(dc, mc, active and active[k], originals, path, k)
			if(ne) then need_exec = true end
			if(wd) then work_done = true end
			if(cn) then delta[k] = nil end
		end
::continue::
	end
	--
	-- if we have been added, deleted, or changed then we need to exec
	--
	if(delta._added or delta._deleted or delta._changed) then need_exec = true end

	--
	-- if we are ready then check our dependencies and execute if 
	--	
	if(func and need_exec) then
		--
		-- check our dependencies
		--
		if(not dependencies_met(path, originals)) then
			print("PATH: " .. path.. " -- DEPS FAIL")
			return false, work_done, false
		end

		print("PATH: " .. path.. " -- EXEC (key="..key..")")
		local rc, err = pcall(func, path, key, delta, master)
		if(not rc) then
			print("Call failed.")
			print("ERR: " .. err)
		end

		-- we need to parent at this point to apply the deltas, at least if its
		-- a delete?? 

		-- TODO: apply the delta changes if we are successful
		-- TODO: find a way of propogating errors back up (return nil?)

		work_done = true
		clear_node = true
	end

	--
	-- If delta doesn't have anything left in it then we need to signal
	-- the key to be cleared
	--
	if(not has_children(delta)) then clear_node = true end
	return need_exec, work_done, clear_node
end

function commit_delta(delta, master, active, originals)
	while(1) do
		local need_exec, work_done = new_do_delta(delta, master, active, originals)
		if(not work_done) then
			print("NO WORK DONE")
			break
		end
		for k,v in pairs(delta) do
			print("STILL HAVE: "..k)
		end
		local a = count_elements(delta)
		print("A="..a)
		if(a == 0) then
			break
		end
	end
end


-- cc = read_config("sample", CONFIG.master)
-- print(show_config(cc, nil, CONFIG.master))

--op = show_config(CONFIG.active, CONFIG.delta, CONFIG.master)
--print(op)


--show_config(CONFIG.active, nil, CONFIG.master)
--process_delta(CONFIG.delta, CONFIG.master, CONFIG.active)
--op = show_config(CONFIG.active, CONFIG.master)
--print(op)

commit_delta(CONFIG.delta, CONFIG.master, CONFIG.active, CONFIG)

--apply_delta(CONFIG.active, CONFIG.delta, "interface")

--node_walk("", t, delta, delta, t)
--node_exists("fred/bill/joe", {})
--node_exists("blah", {})
--

--local d, m = get_tables("interface/ethernet/4", delta, t )

--print("D=" .. tostring(d))
--print("M=" .. tostring(m))


