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
--require("config_io")			-- allow reading and writing of configs

--
-- global: master
--
-- This is the main structural table, it defines how the various sections
-- operate and what dependencies exist
--
CONFIG = {}
CONFIG.master = {
	["dns"] = {
		_depends = { "/interface", "/interface/ethernet/0" },
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

function copy_table(t) 
	local rc = {}
	for k, v in pairs(t) do
		if(type(v) == "table") then rc[k] = copy_table(v)
		else rc[k] = v end
	end
	return rc
end

CONFIG.delta = copy_table(CONFIG.active)
CONFIG.delta["dns"]._changed = 1
CONFIG.delta["dns"]._fields_changed =  { ["resolvers"] = 1 }
CONFIG.delta["dns"].resolvers = { "8.8.8.8", "1.1.2.1", "2.2.2.2" }
CONFIG.delta["dns"].resolvers._original_list = CONFIG.active["dns"].resolvers
CONFIG.delta["dns"].resolvers._items_deleted = { "8.8.4.4" }
CONFIG.delta["dns"].resolvers._items_added = { "1.1.1.1", "2.2.2.2" }

CONFIG.delta.test = {}
CONFIG.delta.test._added = 1
CONFIG.delta.test.test2 = {}
CONFIG.delta.test.test2._added = 1
CONFIG.delta.test.test2.test3 = {}
CONFIG.delta.test.test2.test3._added = 1
CONFIG.delta.test.test2.test3.test4 = {}
CONFIG.delta.test.test2.test3.test4._added = 1
CONFIG.delta.test.test2.test3.test4.value = 77

CONFIG.delta.fred = {}
CONFIG.delta.fred._added = 1
CONFIG.delta.fred.one = {}
CONFIG.delta.fred.one._added = 1
CONFIG.delta.fred.one.value = "blah"

CONFIG.delta.interface._changed = 1
CONFIG.delta.interface.ethernet._changed = 1
CONFIG.delta.interface.ethernet["0"]._changed = 1
CONFIG.delta.interface.ethernet["0"]._fields_added = { ["mtu"] = 1, ["duplex"] = 1, ["speed"] = 1 }
CONFIG.delta.interface.ethernet["0"]._fields_deleted = { ["grog"] = 1 }
CONFIG.delta.interface.ethernet["0"].mtu = 1500
CONFIG.delta.interface.ethernet["0"].duplex = "auto"
CONFIG.delta.interface.ethernet["0"].speed = "auto"

CONFIG.delta.interface.ethernet["1"] = {}
CONFIG.delta.interface.ethernet["1"]._added = 1
CONFIG.delta.interface.ethernet["1"].name = "eth1"
CONFIG.delta.interface.ethernet["1"].address = "192.168.1.1/24"
CONFIG.delta.interface.ethernet["1"].comment = { "two", "line comment",
										_added = 1
									}

tmp = CONFIG.delta.interface.ethernet["2"]
CONFIG.delta.interface.ethernet["2"] = {}
CONFIG.delta.interface.ethernet["2"]._deleted = tmp



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
-- if we have any non-list tables then we have children
--
function has_children(node)
	for k, v in pairs(node) do
		if(string.sub(k, 1, 1) ~= "_") then
			if(type(v) == "table" and not v[1]) then return true end
		end
	end
	return false
end
function is_in_list(list, item)
	for _,v in ipairs(list) do if(v == item) then return true end end
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
function append_list(orig, extra)
	for _, v in ipairs(extra) do table.insert(orig, v) end
end

--
-- Return all the fields from the master definition in the supplied order
-- or alphabetically. We also add comment on the front if it's not included
--
function list_all_fields(master)
	local rc = {}
	if(master._order) then 
		rc = master._order 
	else
		for k, v in pairs(master) do
			if(string.sub(k, 1, 1) ~= "_") then table.insert(rc, k) end
		end
		table.sort(rc)
	end
	if(not is_in_list(rc, "comment")) then
		table.insert(rc, 1, "comment")
	end
	return rc
end

--
-- list any non directive children, sorted alphabetically
--
function children_alphabetically(delta)
	local rc = {}
	for k,_ in pairs(delta) do 
		if(string.sub(k, 1, 1) ~= "_") then table.insert(rc, k) end
	end
	table.sort(rc)
	return rc
end

--
-- pull out any children from the delta that are a wildcard match, we will
-- use this in list_children to cover the ["*"] entry in _order
--
function list_all_wildcards(delta, master)
	local rc = {}
	if(not master["*"]) then return rc end
	for k,_ in pairs(delta) do
		if(not master[k]) then table.insert(rc, k) end
	end
	table.sort(rc)
	return rc
end

--
-- Return the list of our children in the defined order or alphabetically.
-- We also add comment on the front if it's not included.
--
function list_children(delta, master)
	local kids = children_alphabetically(delta)
	local order = master._order or {}
	local rc = {}

	-- put comment at the front if we have one
	if(is_in_list(kids, "comment")) then
		table.insert(rc, "comment")
		remove_from_list(kids, "comment")
	end

	-- start with the ones from order, cater for "*"
	for _,k in ipairs(order) do
		if(is_in_list(kids, k)) then
			table.insert(rc, k)
			remove_from_list(kids, k)
		elseif(k == "*") then
			append_list(rc, list_all_wildcards(delta, master))
		end
	end

	-- now anything left over...
	append_list(rc, kids)
	return rc
end

--
-- Use the information in the list structure to show the original list with
-- adds and deletes highlighted.
--
function show_list(item, list, indent)
	local base = (list._added and {}) or list._original_list or list
	local dels = (list._items_deleted and copy_table(list._items_deleted)) or {}
	local adds = (list._added and list) or list._items_added or {}

	for _, k in ipairs(base) do
		local operation = " "
		if(is_in_list(dels, k)) then
			operation = "-"
			remove_from_list(dels, k)
		end
		print(operation .. " " .. string.rep(" ", indent) .. item .. " " .. k)
	end
	for _, k in ipairs(adds) do 
		print("+ " .. string.rep(" ", indent) .. item .. " " .. k) 
	end
end

function show_fields(delta, master, indent)
	local fields = list_all_fields(master)
	
	--
	-- if we are fully deleted then we show the deleted fields
	-- all first
	--
	if(delta._deleted) then
		for _, k in ipairs(fields) do
			if(delta._deleted[k]) then
				print("- " .. string.rep(" ", indent) .. k .. "=" .. tostring(delta._deleted[k]))
			end
		end
	end

	--
	-- now show the less dramatic adds, deletes and changes
	--
	for _, k in ipairs(fields) do
		if(delta[k]) then
			local operation = " "
			if(delta._added) then operation = "+"
			elseif(delta._fields_added and delta._fields_added[k]) then operation = "+"
			elseif(delta._fields_deleted and delta._fields_deleted[k]) then operation = "-"
			elseif(delta._fields_changed and delta._fields_changed[k]) then operation = "|" end

			if(type(delta[k]) == "table") then
				show_list(k, delta[k], indent)
			else
				print(operation .. " " .. string.rep(" ", indent) .. k .. "=" .. tostring(delta[k]))
			end
		end
::continue::
	end
end

--
-- Recursive function to show a delta config. We highlight anything that needs to
-- be added or removed (including changes to lists)
--
function show_config(delta, master, indent, parent)
	indent = indent or 0

	for _, k in ipairs(list_children(delta, master)) do
		local dc = delta[k]
		local mc = master[k] or master["*"]
		if(not mc) then 
			print("WARNING: no master definition for: "..k)
			goto continue
		end

		-- work out how we need to be shown
		local operation = " "
		if(dc._added) then operation = "+"
		elseif(dc._deleted) then operation = "-"
		elseif(dc._changed) then operation = "|" end

		local label = (parent and (parent.." "..k)) or k

		-- show the header (but only if we don't have wildcard children
		if(mc["*"]) then
			show_config(dc, mc, indent, k)
		else
			print(operation .. " " .. string.rep(" ", indent) .. label .. " {")
			if(has_children(dc)) then
				show_config(dc, mc, indent+4, child_label)
			else
				show_fields(dc, mc, indent+4)
			end
			print(operation .. " " .. string.rep(" ", indent) .. "}")
		end
::continue::
	end
end

--
-- Cleaning a config is simply removing any of the directives in a recursive 
-- fashion. If we end up removing everything then we return nil so the result
-- should be applied to the table (i.e. fred = clean_config(fred))
--
function clean_config(delta)
	for k,v in pairs(delta) do
		if(string.sub(k, 1, 1) == "_") then delta[k] = nil
		elseif(type(v) == "table") then delta[k] = clean_config(delta[k]) end
	end
	if(not next(delta)) then return nil end
	return delta
end

--
-- Applying a delta is walking through the delta tree (ignoring any children
-- that have not changed), and then executing any functions that we find
--
-- Before executing the function we need to make sure any dependencies are
-- met
--
function apply_delta(delta, active, master, originals, completed, ppath)
	-- setup some default for our internal vars
	ppath = ppath or ""

	-- flag to show whether we actualy did anything or not
	local did_work = false

	for _, k in ipairs(list_children(delta, master)) do
		local path = ppath .. "/" .. k
		local dc = delta[k]
		local mc = master[k] or master["*"]
		if(not mc) then 
			print("WARNING: no master definition for: "..k)
			goto continue
		end
		if(not active[k]) then active[k] = {} end
		local ac = active[k]

		-- we only care about stuff that has changed in some way
		if(dc._added or dc._deleted or dc._changed) then
			-- TODO: check dependencies are met
			if(mc._depends) then
				for _,d in ipairs(mc._depends) do
					if(not completed[d]) then
						print("Dependency not complete: " .. d)
						goto continue
					end
				end
			end
			
			if(mc._function) then
				print("Would execute")
				did_work = true
				-- TODO: return nil,err on failure
			elseif(has_children(dc)) then
				local dw, err = apply_delta(dc, ac, mc, originals, completed, path)
				if(dw == nil) then return nil, err end
				if(dw) then did_work = true end
			end
			-- move the config across, and clean
			delta[k] = clean_config(delta[k])
			active[k] = delta[k]
		end
		completed[path] = 1
		print("Done: " .. path)
::continue::
	end
	return did_work
end

function commit_delta(delta, active, master, originals)
	local completed = {}
	while(1) do
		print("RUN")
		local dw, err = apply_delta(delta, active, master, originals, completed)
		if(dw == nil) then
			print("ERROR: " .. err)
			break
		end
		if(not dw) then
			print("NO WORK")
			break
		end
		for k,v in pairs(delta) do
			print("Srill left: " .. k)
		end
	end
end

--show_config(CONFIG.delta, CONFIG.active, CONFIG.master)
commit_delta(CONFIG.delta, CONFIG.active, CONFIG.master, CONFIG)
dump(CONFIG.active)

--[[
dump(CONFIG.delta)
print("---------------------------")
CONFIG.delta = clean_config(CONFIG.delta)
dump(CONFIG.delta)
]]--

