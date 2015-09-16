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
require("base64")
--require("config_io")			-- allow reading and writing of configs

--
-- global: master
--
-- This is the main structural table, it defines how the various sections
-- operate and what dependencies exist
--
CONFIG = {}
CONFIG.master = {
	["dnsmasq"] = {
		_function = function() return true end,
		_depends = { "/interface/ethernet/0" },
		_hidden = 1,
		["dns"] = {
			["resolvers"] = {
				_type = "list/ipv4",
				_syntax = "syntax_ipv4",
			},
			["set"] = {
				_type = "blah"
			}
		},
		["dhcp"] = {
			["lee"] = { _type = "blarg" },
		},
	},
	["tinc"] = {
		_depends = { "interface", "dns" }
	},
	["fred"] = {
		_show_together = 1,
--		_function = function() return true end,
--		_depends = { "/interface/ethernet" },
		["*"] = {
--			_function = function() return true end,
			["value"] = {
				_type = "blah"
			}
		},
		["new"] = {
			["dns"] = { _link = "/dnsmasq/dns" }
		},
		["xxx"] = {
			["aaa"] = { _type = "blah" },
			["bbb"] = { _type = "blah" },
			["ccc"] = { _type = "blah" },
		},
		["lee"] = {
			_type = "file/text"
		}
	},
	["test"] = {
		["test2"] = {
			["test3"] = {
				["dhcp"] = { _link = "/dnsmasq/dhcp" },
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

--CONFIG.master["fred"]["new"]["dns"] = CONFIG.master["dnsmasq"]["dns"]
--CONFIG.master["test"]["test2"]["test3"]["dhcp"] = CONFIG.master["dnsmasq"]["dhcp"]

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
		["dnsmasq"] = {
			["dns"] = {
				resolvers = { "r1", "r2" }
			}
		},
--		["dns"] = {
--			resolvers = { "8.8.8.8", "8.8.4.4" }
--		},
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
function same_list(a, b)
	if(#a ~= #b) then return false end
	for i=1,#a do
		if(a[i] ~= b[i]) then return false end
	end
	return true
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
			if(string.sub(last, 1, 1) ~= "_") then return last, t[last] end
		end
	end
end

--
-- remove all directives (non-recursively)
--
function remove_directives(t)
	for k,_ in pairs(t) do
		if(string.sub(k, 1, 1) == "_") then t[k] = nil end
	end
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

--
-- Handle the display of both binary and text files
--
function show_file(operation, ftype, k, value, indent, dump)
	ftype = string.sub(ftype, 6)

	print(operation .. " " .. string.rep(" ", indent) .. k .. " <" .. ftype .. ">")
	if(ftype == "binary") then
		local binary = enc(value)

		for i=1, #binary, 76 do
			print(operation .. " " .. string.rep(" ", indent+4) .. string.sub(binary, i, i+75))
			if(not dump) then
				if(i >= 77*4) then
					print(operation .. " " .. string.rep(" ", indent+4) .. "... (total " .. #binary .. " bytes)")
					break
				end
			end
		end
	elseif(ftype == "text") then
		local lc = 0
		for line in string.gmatch(value, "([^\n]*)\n?") do
			print(operation .. " " .. string.rep(" ", indent+4) .. "|" .. line)
			if(not dump) then
				lc = lc + 1
				if(lc >= 4) then
					print(operation .. " " .. string.rep(" ", indent+4) .. "... <more>")
					break
				end
			end
		end
		if(dump) then print(operation .. " " .. string.rep(" ", indent+4) .. "<eof>") end
	end
end

--
-- Disply and individual field with the appropriate disposition, we use
-- a separate function to cover lists
--
function show_field(delta, master, indent, k, dump)
	local value = delta[k] or (delta._fields_deleted and delta._fields_deleted[k])
	if(value) then
		local operation = " "

		if(delta._added) then operation = "+"
		elseif(delta._fields_added and delta._fields_added[k]) then operation = "+"
		elseif(delta._fields_deleted and delta._fields_deleted[k]) then operation = "-"
		elseif(delta._fields_changed and delta._fields_changed[k]) then operation = "|" end

		if(k == "comment" and not dump) then k = "#" end

		if(type(value) == "table") then
			show_list(operation, k, value, indent)
		elseif(string.sub(master[k]._type, 1, 5) == "file/") then
			show_file(operation, master[k]._type, k, value, indent, dump)
		else
			print(operation .. " " .. string.rep(" ", indent) .. k .. " " .. tostring(value))
		end
	end
end

--
-- For a given node, start by showing comments, then the fields. Then recurse
-- into the containers.
--
function show_config(delta, master, indent, parent, p_op)
	indent = indent or 0
	p_op = p_op or " "

	if(delta["comment"] or (delta._fields_deleted and delta._fields_deleted["comment"])) then
		show_field(delta, master, indent, "comment")
	end
	if(has_non_comment_fields(delta, master)) then
		local item_indent = indent
		if(parent) then 
			print(p_op .. " " .. string.rep(" ", indent) .. parent .. " (settings) {") 
			item_indent = item_indent + 4
		end
		for k in each_field(delta, master) do
			if(k ~= "comment") then show_field(delta, master, item_indent, k) end
		end
		if(parent) then print(p_op .. " " .. string.rep(" ", indent) .. "}") end
	end

	for k, dc, mc in each_container(delta, master) do
		local label = (parent and (parent .. " " .. k)) or k
		if(mc._link) then mc = mc._link_mc end

		-- work out how we need to be shown, we'll ignore change for containers
		local operation = " "
		if(dc._added) then operation = "+"
		elseif(dc._deleted) then operation = "-" end

		if(mc._show_together) then
			show_config(dc, mc, indent, k, operation)
		elseif(not mc._hiddenX) then
			print(operation .. " " .. string.rep(" ", indent) .. label .. " {")
			show_config(dc, mc, indent+4)
			print(operation .. " " .. string.rep(" ", indent) .. "}")
		end
	end
end
function dump_config(delta, master, indent)
	indent = indent or 0
	for k in each_field(delta, master) do
		show_field(delta, master, indent, k, true)
	end
	for k, dc, mc in each_container(delta, master) do
		if(mc._link) then mc = mc._link_mc end
		if(not mc._hiddenX) then
			print("  " .. string.rep(" ", indent) .. k .. " {")
			dump_config(dc, mc, indent+4)
			print("  " .. string.rep(" ", indent) .. "}")
		end
	end
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

		-- skip empty lines
		if(string.match(line, "^%s*$")) then goto continue end

		-- if we get a close bracket then we need to return, so exit the loop
		if(string.match(line, "}$")) then break end

		-- look for a section start
		local sec = string.match(line, "^%s*([^%s]+)%s+{$")
		if(sec) then
			local mc = master and (master[sec] or master["*"])
			local ac

			-- handle links by sorting the mc
			if(mc._link) then mc = mc._link_mc end

			--
			-- we have a section start, but we only fill in the return
			-- if we had an equivalent master to follow
			--
			ac = read_config(nil, mc, file)
			if(mc) then rc[sec] = ac end
		else
			--
			-- this should be a field, but could include a file type
			--
			local key, value = string.match(line, "^%s*([^%s]+)%s+(.*)$")
			if(not key) then
				print("FIELD ERROR: " .. line)
			else
				local mc = master and master[key]
				local is_list = mc and mc._type and string.sub(mc._type, 1, 5) == "list/"
				local is_file = mc and mc._type and string.sub(mc._type, 1, 5) == "file/"

				if(is_list) then
					if(not rc[key]) then rc[key] = {} end
					table.insert(rc[key], value)
				elseif(is_file) then
					local data = ""

					while(1) do
						local line = file:read()
						if(mc._type == "file/binary") then
							line = string.gsub(line, "^%s+", "")
							data = data .. line
							if(string.match(line, "==$")) then
								rc[key] = dec(data)
								break;
							end
						elseif(mc._type == "file/text") then
							if(string.match(line, "^%s+<eof>")) then
								rc[key] = data
								break;
							end
							line = string.gsub(line, "^%s+|", "")
							if(#data > 0) then data = data .. "\n" end
							data = data .. line
						end
					end
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
	--TODO: run through and handle links?
	--		if we find a link, then build the dest and link the table over?
	if(filename) then 
		file:close() 
		recreate_links(rc, master)
	end
	return rc
end

function recreate_links(active, master, gactive)
	-- store a ref to the top level active structure
	gactive = gactive or active

	-- go through each container
	for k, ac, mc in each_container(active, master) do
		print("RCL: " .. k)
		if(mc._link) then
			print("Link node called for: "..mc._link)
			link_node(gactive, ac, mc._link)
		else
			recreate_links(ac, mc, gactive)
		end
	end
end

--
-- Applying a delta is walking through the delta tree (ignoring any children
-- that have not changed), and then executing any functions that we find
--
-- Before executing the function we need to make sure any dependencies are
-- met
--
function apply_delta(delta, master, active, gconfig, path)
	-- internal vars
	path = path or ""

	-- keep track of whether we did anything
	local did_work = false

	-- if nothing changed we do nothing
	if(not delta._added and not delta._deleted and not delta._changed) then return false end

	-- if we have a function the we need to take action (even if no_exec)
	if(master._function) then
		if(not delta._no_exec) then
			-- check dependencies
			for _, d in ipairs(master._depends or {}) do
				print("Checking dependency: " .. d)
				if(has_outstanding_changes(d, gconfig.master, gconfig.delta)) then
					print("Dependency not met for: "..d)
					return false
				end
			end
			
			-- run the function
			print("Would Execute: " .. path)
		end
		migrate_delta_to_active(delta, master, active, gconfig, true)
		return true
	end

	-- if we didn't have a function then we need to run over the containers
	-- processing them
	for k, dc, mc in each_container(delta, master) do
		-- make sure we have the active structure
		active[k] = active[k] or {}
		if(apply_delta(dc, mc, active[k], gconfig, path .. "/" .. k)) then
			did_work = true
		end
	end

	-- if we didn't have a function then we just migrate any changed fields over
	-- there shouldn't really be any other than comments (no recurse)
	migrate_delta_to_active(delta, master, active, gconfig, false)
	return did_work
end


--
-- copy a table recursively but don't take any of the directives, if we
-- end up empty then return nil
--
function clean_copy(delta)
	local rc = {}

	for k,v in non_directive_fields(delta) do
		if(type(v) == "table") then rc[k] = clean_copy(v)
		else rc[k] = v end
	end
	if(not next(rc)) then return nil end
	return rc
end

-- Go through each field and set it appropriately in the active config, if we are recursing
-- the we also handle each child (unless it's a link, in which case we leave it alone)
function migrate_delta_to_active(delta, master, active, gconfig, recurse)

	-- if we are a link then we don't do anything here, it will happen
	-- on the other end
	if(master._link) then return end

	for k in each_field(delta, master) do
		-- if we are not in the delta then we are deleted
		if(not delta[k]) then
			active[k] = nil
			goto continue
		end

		-- create the active structure if needed
		if(not active[k]) then active[k] = {} end

		-- if we are a table then we will clean and copy
		if(type(delta[k]) == "table") then
			active[k] = clean_copy(delta[k])
			delta[k] = clean_copy(delta[k])
		else
			active[k] = delta[k]
		end
::continue::
	end
	delta._fields_added = nil
	delta._fields_deleted = nil
	delta._fields_changed = nil

	if(recurse) then
		for k, dc, mc in each_container(delta, master) do
			-- if we are deleted in the delta then we are gone...
			if(dc._deleted) then
				delta[k] = nil
				active[k] = nil
			else
				-- make the active structure if needed
				if(not active[k]) then active[k] = {} end
			
				migrate_delta_to_active(dc, mc, active[k], gconfig, recurse)
			end
		end
	end

	set_node_status(delta, master)

	-- if we were the original part of the link then we need to link ourselves back 
	-- to the pointer bit.
	if(master._link_dests) then
		for _, k in ipairs(master._link_dests) do link_node(gconfig.active, active, k) end
	end
end


--
-- Keep running through the apply_delta function until we don't
-- do any work, then we should be finished.
--
function commit_delta(delta, master, active, gconfig)
	while(1) do
		print("RUN")
		local did_work, err = apply_delta(delta, master, active, gconfig)
		if(did_work == nil) then
			print("ERROR: " .. err)
			break
		end
		if(not did_work) then
			print("NO WORK")
			break
		end
		for k in each_container(delta, master) do
			if(delta[k]._added or delta[k]._deleted or delta[k].changed) then
				print("Still change to do for: " .. k)
			end
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
-- For a given node, see if we have outstanding changes
--
function has_outstanding_changes(path, m, d)
	local mc, dc = get_node(path, m, d)
	if(mc and dc and (dc._added or dc._deleted or dc._changed)) then return true end
	return false
end

--
-- an iterator function that goes through our list of key=value fields
-- fields so we return either key,value or field,nil with + or - for list
-- operations
--
function field_values(t)
	local i = 0
	local n = #t
	return function()
		i = i + 1
		if(t[i]) then
			local k, op, v = string.match(t[i], "^(%a[^=]-)([+-]?)=(.*)$")
			if(op and #op == 0) then op = nil end
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
-- Function to delete a given section of the config, this means deleting
-- any individual fields and then recursing into any containers.
--
-- We pass path in on the first call only to identify the top level call
--
function delete_config(delta, master, path)
	local mc = master
	local dc = delta
	-- if we have a path provided then we are top level, otherwise we are recursing
	if(path) then
		mc, dc = get_node(path, master, delta)
		if(not mc or not dc) then
			print("Xinvalid path: " .. path)
			return false
		end
	end

	-- TODO: handle links in the same way as alter_config (here and at the end)

	-- start by recursing into the containers
	for k in each_container(dc, mc) do
		delete_config(dc[k], mc[k])
	end

	-- now delete each of the fields
	if(not dc._fields_deleted) then dc._fields_deleted = {} end
	for k in each_field(dc, mc) do
		if(dc._fields_added and dc._fields_added[k]) then
			-- do nothing
		elseif(dc._fields_updated and dc._fields_updated[k]) then
			dc._fields_deleted[k] = dc._fields_updated[k]
		else
			dc._fields_deleted[k] = dc[k]
		end
		dc[k] = nil
	end
	dc._fields_updated = nil
	dc._fields_added = nil
	if(not next(dc._fields_deleted)) then dc._fields_deleted = nil end

	dc._deleted = 1
	dc._added = nil
	dc._changed = nil

	--
	-- if we are the top level, then we will have "path" so we can run
	-- through and re-eval change status for our parent structure
	--
	if(path) then parent_status_update(delta, master, path) end
end

--
-- revert a given section of config by making sure everything is back to
-- normal.
-- 1. put all _fields_deleted and _updated_fields back
-- 2. delete all _fields_added
-- 3. remove all directives
--
function revert_config(delta, master, path)
	local mc = master
	local dc = delta
	-- if we have a path provided then we are top level, otherwise we are recursing
	if(path) then
		mc, dc = get_node(path, master, delta)
		if(not mc or not dc) then
			print("invalid path: " .. path)
			return false
		end
	end

	-- TODO: handle links (see alter/delete)

	for k in each_container(dc, mc) do
		revert_config(dc[k], mc[k])
	end

	for k in each_field(dc, mc) do
		if(dc._fields_deleted and dc._fields_deleted[k]) then
			dc[k] = dc._fields_deleted[k]
			dc._fields_deleted[k] = nil
		end
		if(dc._fields_changed and dc._fields_changed[k]) then
			if(type(dc[k]) == "table" and dc[k]._original_list) then
				dc[k] = dc[k]._original_list
			else
				dc[k] = dc._fields_changed[k]
			end
			dc._fields_changed[k] = nil
		end
		if(dc._fields_added and dc._fields_added[k]) then
			dc[k] = nil
			dc._fields_added[k] = nil
		end
	end
	remove_directives(dc)

	--
	-- if we are the top level, then we will have "path" so we can run
	-- through and re-eval change status for our parent structure
	--
	if(path) then parent_status_update(delta, master, path) end
end

--
-- Set <node> field=value field=value ...
-- delete <node> [field] [field]
--
function alter_config(delta, master, path, fields)
	local only_delete = true
	local orig_path

	-- check the node is valid
	local mc, dc = get_node(path, master, delta)
	if(not mc) then
		print("invalid path: " .. path)
		return false
	end

	-- if we are a link then we need to adjust our mc,dc
	if(mc._link) then
		orig_path = path
		path = mc._link
		mc, dc = get_node(path, master, delta)
		if(not mc) then
			print("invalid link path: " .. path)
			return false
		end
		print("after getnode: "..path.." (orig="..orig_path..") dc="..tostring(dc))
	end

	-- if we are a delete operation then we need to recurse
	-- into all children and mark them, and then clear out the fields
	if(not fields) then
		print("DELETING: before")
		dump(dc)
		delete_config(dc, mc)
		print("AFTER: before")
		dump(dc)
		goto cleanup
	end

	-- check all the supplied fields are valid, if we are a comment
	-- then we create the master entry
	for k, v, op in field_values(fields) do
		if(not mc[k] or mc[k]._has_children) then
			print("invalid field: " .. k)
			return false
		end
		if(op and string.sub(mc[k]._type, 1, 5) ~= "list/") then
			print("list operation on non-list: " .. k)
			return false
		end

		-- if we are a file type then we just check we can open
		-- it here, so we know it will work later...
		if(string.sub(mc[k]._type, 1, 5) == "file/" and v) then
			local file = io.open(v)
			if(not file) then
				print("invalid file: " .. v)
				return false
			end
			file:close()
		end

		if(v or op ~= "-") then only_delete=false end
		-- todo: validate if not del
	end

	-- if we are adding or changing then at this point we know we
	-- are going to be successful (we can't fail) so we can build
	-- the structure to support the change if it's not present
	if(not only_delete) then
		mc = master
		dc = delta
		for key in string.gmatch(path, "([^/]+)") do
			mc = mc[key] or mc["*"]
			if(not dc[key]) then dc[key] = {} end
			dc = dc[key]
		end
	end

	-- now we can make the actual change to the node
	alter_node(dc, mc, fields)

::cleanup::
	parent_status_update(delta, master, path)

	-- if we are a link then we need to make sure we reference the
	-- real_path location
	if(orig_path) then
		-- make orig path
		-- set the dc to the one we've just set
		-- update our patent status
--		local parent, node = string.match(orig_path, "^(.*)/([^/]+)$")
--		local d = make_path(delta, parent)
--		d[node] = dc
		print("LINKING: " .. orig_path)
		link_node(delta, dc, orig_path)
		parent_status_update(delta, master, orig_path)
	end
end

--
-- given a table (typically delta or active) a current node and a
-- destination path, create the dest as a link to current.
--
function link_node(t, src, path)
	local parent, node = string.match(path, "^(.*)/([^/]+)$")
	local new = make_path(t, parent)
	new[node] = src
end

--
-- Once we've changed a node we need to revisit all the parent nodes
-- to make sure the added/removed/changed status is correct
--
function parent_status_update(delta, master, path)
	while(#path > 0) do
		path = string.gsub(path, "/[^/]+$", "")
		mc, dc = get_node(path, master, delta)
		set_node_status(dc, mc)
	end
end

--
-- Look at all the fields and containers and work out whether we should
-- be flagged as "added", "deleted", "changed", or not flagged at all
--
-- If the only changes are _no_exec ones then we set _no_exec
--
function set_node_status(dc, mc)
	-- we will flag certain stuff
	local adds = 0
	local dels = 0
	local changes = 0
	local static = 0
	local no_exec = 0

	-- first check for field related stuff
	for k in each_field(dc, mc) do
		local chg = true

		if(dc._fields_added and dc._fields_added[k]) then adds = adds + 1
		elseif(dc._fields_deleted and dc._fields_deleted[k]) then dels = dels + 1
		elseif(dc._fields_changed and dc._fields_changed[k]) then changes = changes + 1
		else static = static + 1 chg = false end

		-- if we have a change, see if we are a no_exec one...
		if(chg and mc[k]._no_exec) then no_exec = no_exec + 1 end
	end

	-- now process each of the containers we have
	for k in each_container(dc, mc) do
		local chg = true

		if(dc[k]._added) then adds = adds + 1
		elseif(dc[k]._deleted) then dels = dels + 1 
		elseif(dc[k]._changed) then changes = changes + 1
		else static = static + 1 chg = false end

		-- clear out any empty ones
		if(not next(dc[k])) then dc[k] = nil end

		-- if we have a change, see if we are a no_exec one...
		if(chg and dc[k]._no_exec) then no_exec = no_exec + 1 end
	end

	-- set the final status
	dc._added = nil dc._deleted = nil dc._changed = nil
	if(adds + dels + changes + static == 0) then -- do nothing
	elseif(dels + changes + static == 0) then dc._added = 1
	elseif(adds + changes + static == 0) then dc._deleted = 1
	elseif(adds + dels + changes > 0) then dc._changed = 1 end

	dc._no_exec = ((no_exec > 0 and no_exec == adds+dels+changes) and 1) or nil
end	

function alter_list(dc, k, value, list_op)
	-- if we are delteing from a list, make sure the item is there.
	-- if it's the last item then switch to dull delete since it's the
	-- same as the whole list being deleteted
	if(list_op == "-") then
		if(not dc[k] or not is_in_list(dc[k], value)) then return end
		if(dc[k][1] == value and not dc[k][2]) then value = nil end
	end

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

	-- if we are adding or removing something, but we were shown as deleted then 
	-- we need to undelete our field, and then mark each item as deleted. If we 
	-- weren't present before, then it's a pure add (del is not valid)
	if(dc._fields_deleted[k]) then
		local original = dc._fields_deleted[k]
		dc._fields_deleted[k] = nil
		dc[k] = copy_table(original)
		dc[k]._original_list = copy_table(original)
		dc[k]._items_deleted = copy_table(original)
	elseif(not dc[k]) then
		dc[k] = {}
		dc[k]._original_list = {}
		dc[k]._items_added = {}
	end

	if(not dc[k]._original_list) then dc[k]._original_list = copy_table(dc[k]) end

	if(not list_op or list_op == "+") then
		if(not dc[k]._items_added) then dc[k]._items_added = {} end
		table.insert(dc[k]._items_added, value)
		table.insert(dc[k], value)
	elseif(list_op == "-") then
		if(is_in_list(dc[k], value)) then
			if(not dc[k]._items_deleted) then dc[k]._items_deleted = {} end
			table.insert(dc[k]._items_deleted, value)
			remove_from_list(dc[k], value)
		end
	end

	-- if for some bizarre reason our list is the same as our original list
	-- then we are back to normal and we should reflect that
	if(same_list(dc[k], dc[k]._original_list)) then
		dc[k] = dc[k]._original_list
		dc._fields_changed[k] = nil
		return
	end

	-- if the original list is empty, then we must be an add, otherwise
	-- we are a change
	if(not next(dc[k]._original_list)) then 
		dc._fields_added[k] = 1 
	else
		dc._fields_changed[k] = 1 
	end
end

--
-- Given a list of fields to update, we need to either add remove or change
-- the given field. If the field has no value (no = sign) then its considered
-- as a field delete. For lists we support -= to remove items.
--
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

		-- if we're deleting the field and it doesn't exist or if
		-- it's set to the same value then don't do anything
		if(dc[k] == v) then goto continue end

		-- lists are complicated so we will handle them separately
		if(string.sub(mc[k]._type, 1, 5) == "list/") then
			alter_list(dc, k, v, list_op)
			goto continue
		end

		-- if we are a file then we need to load it in, we should
		-- have checked this will work earlier, so no err checking needed
		if(string.sub(mc[k]._type, 1, 5) == "file/") then
			local file = io.open(v)
			v = file:read("*a")
			file:close()
		end
	
		-- handle field deletion ... it is hasn't been added, and wasn't deleted
		-- before then mark it as deleted.
		-- otherwise we can jut clear up the adds/changes references
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

	-- set the final status
	set_node_status(dc, mc)
end

--
-- Run through the master structure and work out if we have
-- children (_container.)
--
-- Children are detected by recursing through and when we
-- find only fields we don't mark the _container.
--
-- Also add the comment field to every node.
-- Create the _order directive for each node.
--
-- This is a critical function that marks the fields and
-- containers so we can use the 'each_field', 'each_container'
-- functions
--
function prepare_master(master, gmaster, path, has_func)
	-- internal arguments
	gmaster = gmaster or master				-- keep our top level reference
	path = path or ""						-- so we know where we are

	-- tracking variables
	local has_children = nil
	local sorted = master._order or {}
	local unsorted = {}

	if(master._function) then has_func = true end

	if(not is_in_list(sorted, "comment")) then table.insert(sorted, 1, "comment") end

	for k, mc in non_directive_fields(master) do
		local is_list = mc._type and string.sub(mc._type, 1, 5) == "list/"

		if(not is_list) then
			prepare_master(mc, gmaster, path .. "/" .. k, has_func)
			has_children = 1
		end
		if(not is_in_list(sorted, k)) then table.insert(unsorted, k) end
	end
	table.sort(unsorted)
	append_list(sorted, unsorted)

	master._has_children = has_children
	master._order = sorted
	if(not master.comment) then
		master.comment = { _type = "list/comment", _no_exec = 1 }
	end

	-- if we are a link to somewhere else then fill in the _link_mc
	if(master._link) then
		if(has_func) then
			print("LINK within function domain, ignoring: " .. path)
			master._link = nil
		else
			master._has_children = 1
			master._link_mc = get_node(master._link, gmaster)
			if(not master._link_mc._link_dests) then master._link_mc._link_dests = {} end
			table.insert(master._link_mc._link_dests, path)
		end
	end
end

function make_path(t, path)
	for key in string.gmatch(path, "([^/]+)") do
		if(not t[key]) then t[key] = {} end
		t = t[key]
	end
	return t
end

--
-- Functions that return iterators for getting the fields
-- and the containers. Each field will return the fields in the
-- order specified in the master (or alphabetically sorted)
--
function each_field(dc, mc)
	local i = 0
	local order = mc._order

	return function()
		while(1) do
			i = i + 1
			if(not order[i]) then return nil end
			if(dc[order[i]] and not mc[order[i]]._has_children) then return order[i] end
			if(dc._fields_deleted and dc._fields_deleted[order[i]]) then return order[i] end
		end
	end
end
function each_container(dc, mc)
	local clist = {}
	local i = 0

	-- build all the wildcards
	local wild = {}
	if(mc["*"]) then
		for k, _ in pairs(dc) do
			if(string.sub(k, 1, 1) ~= "_" and not mc[k]) then table.insert(wild, k) end
		end
		table.sort(wild)
	end

	-- build the full order
	for _, k in ipairs(mc._order) do
		if(k == "*") then 
			append_list(clist, wild) 
		elseif(mc[k] and mc[k]._has_children) then
			table.insert(clist, k)
		end
	end

	-- now prepare the function...
	return function()
		while(1) do
			i = i + 1
			if(not clist[i]) then return nil end
			if(dc[clist[i]]) then return clist[i], dc[clist[i]], mc[clist[i]] or mc["*"] end
		end
	end
end	
--
-- Some boolean checks for having containers or fields
--
function has_non_comment_fields(dc, mc)
	local fx = each_field(dc, mc)
	local f = fx()
	if(f and f == "comment") then
		f = fx()
	end
	return f and true
end


prepare_master(CONFIG.master)
--dump(CONFIG.master)

CONFIG.active = read_config("sample", CONFIG.master)
CONFIG.delta = copy_table(CONFIG.active)
--show_config(CONFIG.active, CONFIG.master)
--alter_config(CONFIG.delta, CONFIG.master, "/fred", { "lee=tttt" })
--commit_delta(CONFIG.delta, CONFIG.master, CONFIG.active, CONFIG)
--dump_config(CONFIG.active, CONFIG.master)


--alter_config(CONFIG.delta, CONFIG.master, "/fred", { "comment=one", "comment=two", "comment=three" } )
--alter_config(CONFIG.delta, CONFIG.master, "/fred/one", { "value=44" })
--alter_config(CONFIG.delta, CONFIG.master, "/fred/xxx", { "aaa=30", "bbb=20", "ccc=10" })
--alter_config(CONFIG.delta, CONFIG.master, "/interface/ethernet/0", { "secondaries=1.2.3.5",
--										"secondaries=2.3.4.5" })
alter_config(CONFIG.delta, CONFIG.master, "/fred/new/dns" )
--alter_config(CONFIG.delta, CONFIG.master, "/fred/new/dns", { "resolvers=r4" })
--alter_config(CONFIG.delta, CONFIG.master, "/interface/ethernet/2", { "address=1.2.3.4/3" })
--alter_config(CONFIG.delta, CONFIG.master, "/test/test2/test3/dhcp", { "lee=abcdabcd" })
--dump(CONFIG.delta)

print("=================")
commit_delta(CONFIG.delta, CONFIG.master, CONFIG.active, CONFIG)

--dump(CONFIG.delta)
--show_config(CONFIG.delta, CONFIG.master)
dump_config(CONFIG.active, CONFIG.master)
dump(CONFIG.active)
--
--revert_config(CONFIG.delta, CONFIG.master, "/fred/two")
--
--alter_config(CONFIG.delta, CONFIG.master, "/fred/two", { "value=22345" })
--alter_config(CONFIG.delta, CONFIG.master, "/interface/ethernet/2", { "address=1.2.3.4/3" })
--alter_config(CONFIG.delta, CONFIG.master, "/interface/ethernet/2", { "address" })
--dump(CONFIG.delta)
--dump(CONFIG.master)
--revert_config(CONFIG.delta, CONFIG.master, "/interface/ethernet/0")

--dump(CONFIG.delta)
print("=================")
--dump_config(CONFIG.delta, CONFIG.master)


