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
-- given a node, we need to work out if it's an add, change, or
-- delete.
-- delete = no fields (i.e. all in ._fields_deleted
-- add = no fields that aren't in ._fields_added
-- nothing = no directives at all
-- change = anything else
--
function node_disposition(delta)
	-- if we are a container, then it's simple...
	if(has_children(delta)) then
		if(delta._added) then return("+")
		elseif(delta._deleted) then return("-")
		elseif(delta._changed) then return(" ")			-- makes it look better
		else return(" ") end
	end

	-- otherwise process the fields...
	-- steady state first...
	if(not delta._fields_added and not delta._fields_deleted and not delta._fields_changed) then
		return(" ")
	end

	-- now check for other conditions
	local is_added = (delta._fields_added and true) or false
	local is_deleted = (delta._fields_deleted and true) or false

	-- if we think we might be added or deleted then check each field
	if(is_added or is_deleted) then
		for k,v in pairs(delta) do
			if(string.sub(k, 1, 1) ~= "_") then
				is_deleted = false
				if(is_added) then
					if(not delta._fields_added[k]) then
						is_added = false
						break
					end
				end
			end
		end
	end

	-- return the right thing
	if(is_added) then return("+") 
	elseif(is_deleted) then return("-")
	else return("|") end
end

--
-- Use the information in the list structure to show the original list with
-- adds and deletes highlighted.
--
function show_list(parent_op, item, list, indent)
	local base = (list._added and {}) or list._original_list or list
	local dels = (list._items_deleted and copy_table(list._items_deleted)) or {}
	local adds = (list._added and list) or list._items_added or {}

	for _, k in ipairs(base) do
		local operation = (parent_op == "-" and "-") or " "
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
	-- show the adds, deletes and changes
	--
	for _, k in ipairs(fields) do
		value = delta[k] or (delta._fields_deleted and delta._fields_deleted[k])
		if(value) then
			local operation = " "

			if(delta._added) then 
				operation = "+"
			elseif(delta._fields_added and delta._fields_added[k]) then 
				operation = "+"
			elseif(delta._fields_deleted and delta._fields_deleted[k]) then 
				operation = "-"
			elseif(delta._fields_changed and delta._fields_changed[k]) then 
				operation = "|" 
			end

			if(type(value) == "table") then
				show_list(operation, k, value, indent)
			else
				print(operation .. " " .. string.rep(" ", indent) .. k .. "=" .. tostring(value))
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
--		local operation = " "
--		if(dc._added) then operation = "+"
--		elseif(dc._deleted) then operation = "-"
--		elseif(dc._changed) then operation = "|" end
		local operation = node_disposition(dc)

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

--
-- Keep running through the apply_delta function until we don't
-- do any work, then we should be finished.
--
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
			-- TODO: check for changes
			print("Srill left: " .. k)
		end
	end
end

--
-- for a given node, return the master and delta nodes (if they exist)
--
function get_node(path, m, d)
    for key in string.gmatch(path, "([^/]+)") do
        m = m and (m[key] or m["*"])
        d = d and d[key]
    end
    return m, d
end

--
-- an iterator to return non-directive fields
--
function non_directive_fields(t)
	local last = nil
	return function()
		while(1) do
			last = next(t, last)
			if(not last) then return nil end
			if(string.sub(last, 1, 1) ~= "_") then return last end
		end
	end
end

--
-- an iterator function that goes through our list of key=value
-- fields so we return either key,value or field,nil
--
function field_values(t)
	local i = 0
	local n = #t
	return function()
		i = i + 1
		if(t[i]) then
			local k, op, v = string.match(t[i], "^(%a[^=]-)([+-]?)=(.*)$")
			if(#op == 0) then op = nil end
			if(k) then 
				-- convert to a number if it makes sense
				if(string.match(v, "^%-?%d+$") or string.match(v, "^%-?%d*%.%d+$")) then
					v = v + 0
				end
				return k, v, op
			end
		end
		return t[i]
	end
end

--
-- recursively delete (mark) the config from the given
-- node
--
function delete_config(delta, master)
	if(has_children(delta)) then
		for _,k in ipairs(list_children(delta, master)) do
			delete_config(delta[k], master[k])
		end
		delta._changed = nil
		delta._added = nil
	else
		if(not delta._fields_deleted) then delta._fields_deleted = {} end
		for k in non_directive_fields(delta) do
			if(delta._fields_added and delta._fields_added[k]) then
				-- do nothing
			elseif(delta._fields_updated and delta._fields_updated[k]) then
				delta._fields_deleted[k] = delta._fields_updated[k]
			else
				delta._fields_deleted[k] = delta[k]
			end
			delta[k] = nil
		end
		delta._fields_updated = nil
		delta._fields_added = nil
	end
	delta._deleted = 1
end

--
-- Set <node> field=value field=value ...
-- delete <node> [field] [field]
--
function alter_config(delta, master, path, fields)

	-- check the node is valid
	local mc, dc = get_node(path, master, delta)
	if(not mc) then
		print("invalid path: " .. path)
		return false
	end

	-- if we are a delete operation then we need to recurse
	-- into all children and mark them, and then clear out the fields
	if(not fields) then
		delete_config(dc, mc)
		goto cleanup
	end

	-- we shouldn't really get here if we are a container
	if(not has_children(mc)) then
		print("AAARGGGHHHH!!!!")
		return false
	end

	-- check all the supplied fields are valid, remove the leading minus
	-- if we are a list op
	--
	for k, v, op in field_values(fields) do
		if(not mc[k]) then
			print("invalid field: " .. k)
			return false
		end
		if(op and string.sub(mc[k]._type, 1, 5) ~= "list/") then
			print("list operation on non-list: " .. k)
			return false
		end
		-- todo: validate if not del
	end

	-- we know it's going to work, so we can build the structure
	-- we need to contain the node
	mc = master
	dc = delta
    for key in string.gmatch(path, "([^/]+)") do
        mc = mc[key] or mc["*"]
		if(not dc[key]) then dc[key] = {} end
		dc = dc[key]
    end

	-- now we can make the actual change to the node
	alter_node(dc, mc, fields)

::cleanup::
	-- check all the parent nodes and mark them as appropriate
	while(#path > 0) do
		path = string.gsub(path, "/[^/]+$", "")
		mc, dc = get_node(path, master, delta)

		-- prepare
		dc._changed = nil
		dc._added = 1 
		dc._deleted = 1
		
		-- if we only contain adds then we must be add
		-- if we only contain dels then we must be del
		-- if we only contain no change then we must be no change
		-- otherwise we are change
		for k in non_directive_fields(dc) do
			if(dc[k]._added) then dc._deleted = nil dc._changed = 1 end
			if(dc[k]._deleted) then dc._added = nil dc._changed = 1 end
			if(dc[k]._changed) then dc._deleted = nil dc._added = nil dc._changed = 1 end
		end
		if(dc._added or dc._deleted) then dc._changed = nil end
	end
end	

function alter_list(dc, k, value, list_op)
	print("LISTOP: ["..tostring(list_op).."]")
	-- no value means delete the whole list, so this is a revert to original
	-- and then standard treatment for a deleted item
	if(not value) then
		if(not dc._fields_added[k] and not dc._fields_deleted[k]) then
			if(dc[k]._original_list) then dc[k] = dc[k]._original_list end
			dc[k]._items_added = nil
			dc[k]._items_deleted = nil
			dc._fields_deleted[k] = dc[k]
		end
		dc._fields_changed[k] = nil
		dc._fields_added[k] = nil
		dc[k] = nil
		return
	end

	-- if we are deleting (k-=v) then we should find the key ends with a minus
	if(string.match(k, "%-$")) then
		k = string.sub(k, 1, #k-1)
		print("Remove value, k="..k.." v="..tostring(value))
		return
	end

	-- if we are adding something, but we were shown as deleted then we need
	-- to undelete our field, and then mark each item as deleted. If we weren't
	-- present before, then it's a pure add
	if(dc._fields_deleted[k]) then
		local original = dc._fields_deleted[k]
		dc._fields_deleted[k] = nil
		dc[k] = copy_table(original)
		dc[k]._original_list = copy_table(original)
		dc[k]._items_deleted = copy_table(original)
	elseif(not dc[k]) then
		dc[k] = {}
		dc[k]._original_list = {}
		dc[k]._items_added = { v }
	end

	-- if we set a value then it will be a simple add to the list and 
	-- the items_added list
	if(not dc[k]._original_list) then dc[k]._original_list = copy_table(dc[k]) end
	if(not dc[k]._items_added) then dc[k]._items_added = {} end
	table.insert(dc[k]._items_added, value)
	table.insert(dc[k], value)

	-- if the original list is empty, then we must be an add, otherwise
	-- we are a change
	if(not next(dc[k]._original_list)) then 
		dc._fields_added[k] = 1 
	else
		dc._fields_changed[k] = 1 
	end
end

function alter_node(dc, mc, fields)
	-- make sure we have the structures we need in this node
	if(not dc._fields_deleted) then dc._fields_deleted = {} end
	if(not dc._fields_added) then dc._fields_added = {} end
	if(not dc._fields_changed) then dc._fields_changed = {} end
	
	-- now we can set the actual fields
	for k,v, list_op in field_values(fields) do
		local is_added = dc._fields_added[k]
		local deleted_val = dc._fields_deleted[k]
		local changed_val = dc._fields_changed[k]

		-- if we're setting to the same value, then we don't really
		-- want to do anything
		if(dc[k] == v) then goto continue end

		-- handle field deletion ... it is hasn't been added, and wasn't deleted
		-- before then mark it as deleted.
		-- otherwise we can jut clear up the adds/changes references
		if(string.sub(mc[k]._type, 1, 5) == "list/") then
			alter_list(dc, k, v, list_op)
			goto continue
		end
	
		if(v == nil) then
			if(not is_added and not deleted_val) then
				dc._fields_deleted[k] = dc[k]
			end
			dc._fields_changed[k] = nil
			dc._fields_added[k] = nil
			goto set
		end

		-- if we are putting the original, deleted, or changed value back
		-- then we need to remove the changed/deleted status since we
		-- are back to previous
		-- (note that this won't work for a list)
		if(deleted_val == v or changed_val == v) then
			dc._fields_deleted[k] = nil
			dc._fields_changed[k] = nil
			dc._fields_added[k] = nil
			goto set
		end

		-- if we were deleted, but now we are setting a different value
		-- then we need to move to changed
		if(deleted_val) then
			dc._fields_changed[k] = deleted_val
			dc._fields_deleted[k] = nil
			goto set
		end

		-- if the field is already set, then this is either a change or
		-- an overwrite of an existing change or add
		if(dc[k]) then
			if(not changed_val and not is_added) then
				dc._fields_changed[k] = dc[k]
			end
			goto set
		end

		--  if it's not set then this is a simple add ... fall through
		dc._fields_added[k] = 1
::set::	
		-- actually set the value	
		dc[k] = v
::continue::
	end

	-- tidy up the directives...
	if(not next(dc._fields_deleted)) then dc._fields_deleted = nil end
	if(not next(dc._fields_added)) then dc._fields_added = nil end
	if(not next(dc._fields_changed)) then dc._fields_changed = nil end
	dc._added = nil
	dc._deleted = nil
	dc._changed = nil

	-- now we can work out if we are all added, deleted, changed or static
	if(dc._fields_deleted or dc._fields_added or dc._fields_changed) then
		-- if all of our fields are in _fields_added then we are added
		-- if we have nothing but deleted_fields then we are deleted
		local is_added = (dc._fields_added and true) or false
		local is_deleted = (dc._fields_deleted and true) or false
		if(is_added or is_deleted) then
			for k, v in pairs(dc) do
				if(string.sub(k, 1, 1) ~= "_") then
					is_deleted = false
					if(not dc._fields_added or not dc._fields_added[k]) then
						is_added = false
						break
					end
				end
			end
		end
		if(is_added) then dc._added = 1
		elseif(is_deleted) then dc._deleted = 1
		else dc._changed = 1 end
	end
end

CONFIG.delta = {
	interface = {
		ethernet = {
			["0"] = { 
				address = "1.2.3.3/1",
				speed = 40,
				secondaries = { "1.1.1.1/16", "2.2.2.2/8", "3.3.3.3/24" }
			}
		}
	}
}
--alter_config(CONFIG.delta, CONFIG.master, "/interface/ethernet/0", { "secondaries"})
alter_config(CONFIG.delta, CONFIG.master, "/interface/ethernet/0", { "secondaries-=2.2.2.2/8"})
--alter_config(CONFIG.delta, CONFIG.master, "/interface/ethernet/2", { "address=1.2.3.3/1", "speed=40", "duplex=auto" })
--dump(CONFIG.delta)
--show_config(CONFIG.delta, CONFIG.master)
print("--------------")
--alter_config(CONFIG.delta, CONFIG.master, "/interface/ethernet/0", { "address=1.2.3.3/1", "speed=40", "duplex=auto" })
dump(CONFIG.delta)
show_config(CONFIG.delta, CONFIG.master)
print("--------------")
--alter_config(CONFIG.delta, CONFIG.master, "/interface/ethernet/0",
--			{ address="1.6.6.4/8", speed=88 } )
--dump(CONFIG.delta)
print("--------------")
--alter_config(CONFIG.delta, CONFIG.master, "/interface/ethernet/0",
--			{ address=false, speed=40 } )


--show_config(CONFIG.delta, CONFIG.active, CONFIG.master)
--commit_delta(CONFIG.delta, CONFIG.active, CONFIG.master, CONFIG)
--dump(CONFIG.active)

--[[
dump(CONFIG.delta)
print("---------------------------")
CONFIG.delta = clean_config(CONFIG.delta)
dump(CONFIG.delta)
]]--

