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
		_function = function() return true end,
		_partners = { "dhcp" },
		["resolvers"] = {
			_type = "list/ipv4",
			_syntax = "syntax_ipv4",
		},
	},
	["dhcp"] = {
		_depends = { "interface/pppoe" },
		_function = function() return true end,
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
					comment = { 
						_items_added = {"two", "line comment" }
					},
					_added = 1
				},
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
function copy_table(table)
	local rc = {}
	for k, v in pairs(table) do
		if(type(v) == "table") then 
			rc[k] = copy_table(v)
		else
			rc[k] = v
		end
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
	if(p) then table.remove(list, p) end
	return p
end


--
-- process list directives to give a proper 'after' view of a list
-- with the delta applies. We provide a list which will contain the
-- 1,2,3 indexed items and also the _items_added/removed directives
--
function build_list(list, delta)
	-- first process the removes
	if(delta._items_deleted) then
		list._items_deleted = delta._items_deleted
		for _,v in ipairs(delta._items_deleted) do remove_from_list(list, v) end
	end

	-- now add the adds
	if(delta._items_added) then
		list._items_added = delta._items_added
		for _,v in ipairs(delta._items_added) do table.insert(list, v) end
	end
end


--
-- given a delta, master and active we re-create the end state
-- but only for the current level, we don't do children since
-- they will be recursed into
--
function build_config(delta, master, active)
	local rc = {}
	local deleted = delta and delta._deleted
	--
	-- if we are not _deleted, then copy any non-tables from the
	-- active (include lists though)
	--
	if(active and not deleted) then
		for k,v in pairs(active) do
			local mc = master[k] or master["*"]
			local mtype = mc and mc._type

			if(type(v)~= "table") then
				rc[k] = v
			elseif(k == "comment" or (mtype and string.sub(mtype, 1, 5) == "list/")) then
				rc[k] = copy_table(v)
			end
		end
	end

	--
	-- now process the delta, all directives plus any non-tables
	-- this will catch adds and changes (but not list changes)
	-- (TODO: include lists)
	--
	if(delta) then
		for k,v in pairs(delta) do
			local mc = master[k] or master["*"]
			local mtype = mc and mc._type

			if(string.sub(k, 1, 1) == "_" or type(v) ~= "table") then
				rc[k] = v
			elseif(k == "comment" or (mtype and string.sub(mtype, 1, 5) == "list/")) then
				if(not rc[k]) then rc[k] = {} end
				build_list(rc[k], v)
			end
		end
	end

	--
	-- now we process the _fields_deleted directive and remove
	-- any listed fields that need to be removed
	--
	if(rc._fields_deleted) then
		for k,_ in pairs(rc._fields_deleted) do
			rc[k] = nil
		end
	end	
	return rc
end

--
-- given a config with directives, remove all the directives
-- and then if there is nothing left return nil. 
--
function clean_config(config)
	for k,v in pairs(config) do
		if(string.sub(k, 1, 1) == '_') then
			config[k] = nil
		elseif(type(v) == "table") then
			config[k] = clean_config(config[k])
		end
	end

	if(next(config)) then return config end
	return nil
end

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
-- Walk the delta tree looking for changes that need to be processed
-- by a function. If we decide we need to call a function then we
-- check to see if any dependencies (and partner dependencies) are
-- met. That means that none of the dependencies are still showing
-- in the delta (i.e. have uncommitted changes)
--
-- Arguments:
--  delta, master, active -- parents probably containing (key)
--	originals - the global config structure (for deps lookup)
--	path - the parent path
--	key - the item we are looking at (within the parent)
--
--	if key is not set then we just re-use the delta, master, active
--	as this will only be the first call and they will then really
--	be the parents
--
function new_do_delta(dp, mp, ap, originals, path, key)
	-- default to these as ours (for when key not set)
	local delta = dp
	local master = mp
	local active = ap

	-- prepare the path and the config tables for when we have a key
	path = path or ""
	if(key) then 
		path = path .. "/" .. key 
		delta = dp and dp[key]
		master = mp and (mp[key] or mp["*"])

		-- create the active structure if we need to (will be cleaned later)
		if(not ap[key]) then ap[key] = {} end
		active = ap[key]
	end

	--
	-- if we have a function and anything has changed then
	-- we will need to call it (if our dependencies are met)
	--
	local func = master._function
	local need_exec = false
	local work_done = false

	-- create a copy of the active config that we will then modify
	-- using the delta so we have an end state to pass to the func
	local new_config = build_config(delta, master, active)

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
			local ne, wd, nc = new_do_delta(delta, master, active, originals, path, k)
			-- if we get a nil return then wd is the error
			if(ne == nil) then return nil, wd end

			-- otherwise update our status info
			if(ne) then need_exec = true end
			if(wd) then work_done = true end

			-- do we update the config on failure? probably not since we will just fail all
			-- the way back
			new_config[k] = nc
		end
::continue::
	end

	-- if we don't have a key then we can simple exit as we are done.
	if(not key) then return work_done end

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
			return false, work_done, false, new_config
		end

		print("Updating: " .. path)
		print("PATH: " .. path.. " -- EXEC (key="..key..")")
		local rc, err = pcall(func, path, key, delta, master, new_config)
		if(not rc) then
			print("Call failed.")
			print("ERR: " .. err)
			return nil, err
		end

		-- update the config, will be cleaned later...
		ap[key] = new_config

		-- signal we have done something and clear the delta
		work_done = true
		dp[key] = nil
	end

	--
	-- tidy up both the delta and the active config, this will
	-- remove any empty structures
	--
	if(not has_children(delta)) then dp[key] = nil end
	ap[key] = ap[key] and clean_config(ap[key])

	return need_exec, work_done, new_config
end

function commit_delta(delta, master, active, originals)
	while(1) do
		local work_done, err = new_do_delta(delta, master, active, originals)
		if(work_done == nil) then
			print("FAILURE: error=" .. err)
			break;
		end
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
--op = show_config(CONFIG.active, CONFIG.master)
--print(op)

commit_delta(CONFIG.delta, CONFIG.master, CONFIG.active, CONFIG)
dump(CONFIG.active)


--node_walk("", t, delta, delta, t)
--node_exists("fred/bill/joe", {})
--node_exists("blah", {})
--

--local d, m = get_tables("interface/ethernet/4", delta, t )

--print("D=" .. tostring(d))
--print("M=" .. tostring(m))


