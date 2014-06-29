#!./luajit

--
-- Basic lua functions for showing differences between two tables
--

master = {
	["dns"] = {
		["resolvers"] = {
			_type = "fred"
		},
		["billy"] = {
			_type = "fed"
		},
		["abc"] = {
			["yes"] = {
				_type = "fred"
			},
			["no"] = {
				_type = "bool"
			}
		}
	},
	["dhcp"] = {
		_keep_with_children = 1,
		["*"] = {
--			_label = "dhcp ",
			_order = { "fred", "bill" },
			["fred"] = { _type = "xx" },
			["bill"] = { _type = "xx" }
		},
		["blah"] = { _type = 45 },
		["blah2"] = { _type = 45 }
	},
	["x"] = { _type = "xx" }
}

one = {
	["dns"] = {
		resolvers = "yes",
		billy = "hello",
		abc = {
			yes = 1, no = 2
		}
	},
	["dhcp"] = {
		["a"] = {
			fred = 1,
			bill = 2
		},
		["b"] = {
			fred = 50
		},
		["blah"] = 45,
		["blah2"] = "ab"
	}
}

two = {
	["x"] = 1,
	["dhcp"] = {
		["a"] = {
			fred = 5
		}
	}
}


--
-- see if a list contains a particular item
--
function is_in_list(list, item)
	for _,k in ipairs(list) do
		if(k == item) then return true end
	end
	return false
end

--
-- remove a particulare item from a list
--
function remove_from_list(list, item)
	local p = nil
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
-- append a list onto a list
--
function append_list(a, b)
	for _,k in ipairs(b) do
		table.insert(a, k)
	end
end

--
-- dump a table for debugging
--
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
-- returns an iterator that cycles through each field listen in
-- the master (i.e. where _type is defined), the order is determined
-- by looking at the _order definition, and then prepending "comment"
-- (if it's missed) and then adding anything left
--
function each_field(m)
	local i = 0
	return function()
		i = i + 1
		return m._fields[i]
	end
end

--
-- returns an iterator that finds any container contained within a
-- or b, it uses master to work out if it's a container of not. They
-- are iterated in alphabetical order
--
function each_container(a, b, m)
	-- build list of containers from a and b... work out if they are wildcards...
	local keys = {}
	local wildcards = {}
	local clist = {}
	if(a) then for k,_ in pairs(a) do keys[k] = 1 end end
	if(b) then for k,_ in pairs(b) do keys[k] = 1 end end
	for k,_ in pairs(keys) do 
		if(m[k] and not m[k]._type) then	-- container
			table.insert(clist, k)
		elseif(not m[k]) then				-- wildcard
			table.insert(wildcards, k)
		end
	end
	table.sort(wildcards)
	table.sort(clist)
		
	-- now create the list using the order field...
	local containers = {}
	for _,k in ipairs(m._containers) do
		if(k == "*") then 
			append_list(containers, wildcards)
		elseif(is_in_list(clist, k)) then
			table.insert(containers, k)
			remove_from_list(clist, k)
		end
	end
	append_list(containers, clist)

	-- create the iterator function...
	local i = 0
	return function()
		i = i + 1
		return containers[i]
	end
end

--
-- thinking about how to do a list diff...
--
-- the order is important so we can't just do a sorted comparison
-- 1. if items from the original list are not in the second, then show them deleted
-- 2. if there are extra items then they are clearly added
-- 3. if items from the original list are still there, in the same order then "no change"
--
--
-- go through second list .. if we find an item from the first list, then mark any prior ones as deleted
-- mark the item as same.
-- anything not found on the first list is added.
-- anything left in the first list should be shown as deleted
--





function show_fields(a, b, master, indent)
	indent = indent or 0

	for k in each_field(master) do
		local av = a and a[k]
		local bv = b and b[k]
		local value = bv or av
		local mode = " "

		if(value) then
			if(not av) then mode = "+" 
			elseif(not bv) then mode = "-" 
			elseif(av ~= bv) then mode = "|" end

			print(mode .. " " .. string.rep(" ", indent) .. k .. " " .. value)
		end
	end
end

function diff(a, b, master, indent, parent)
	indent = indent or 0

	-- first the fields
	if(parent and each_field(master)()) then
		print("  " .. string.rep(" ", indent) .. parent .. " (settings) {")
		show_fields(a, b, master, indent+4)
		print("  " .. string.rep(" ", indent) .. "}")
	else
		show_fields(a, b, master, indent)
	end

	-- now the containters
	for k in each_container(a, b, master) do
		local mode = " "
		local av = a and a[k]
		local bv = b and b[k]
		local mt = master and (master[k] or master["*"])

		if(av and not bv) then mode = "-" end
		if(bv and not av) then mode = "+" end

		local label = (mt._label or "") .. k

		if(mt._keep_with_children) then
			diff(av, bv, mt, indent, k)
		else
			print(mode .. " " .. string.rep(" ", indent) .. label .. " {")
			diff(av, bv, mt, indent+4)
			print(mode .. " " .. string.rep(" ", indent) .. "}")
		end
::continue::
	end
end

--
-- We do any post processing of the master table so we remove the need
-- to do complex processing later on.
--
-- 1. Build the order field
-- 2. Create the _label options
--

function prepare_master(m, parent_name)
	--
	-- make sure we have a definition for comment in every node
	--
	if(not m["comment"]) then
		m["comment"] = { _type = "string", _no_exec = 1 }
	end

	--
	-- now build a list of what we have in this node, and recurse
	-- at the same time...
	--
	local fields = {}
	local containers = {}

	for k,mv in pairs(m) do
		if(string.sub(k, 1, 1) == "_") then goto continue end

		if(mv._type) then table.insert(fields, k)
		else table.insert(containers, k) end

		-- we need to recurse for any containers...
		if(not mv._type) then prepare_master(mv, k) end

		-- create the label if we are keeping with children
		if(m._keep_with_children) then mv._label = parent_name .. " " end
::continue::
	end

	--
	-- now prepare the _fields and _containers ordered lists
	--
	table.sort(fields)
	table.sort(containers)
	local order = m._order or {}
	local flist = {}
	local clist = {}

	if(not is_in_list(order, "comment")) then table.insert(order, 1, "comment") end

	for _,k in ipairs(order) do
		if(is_in_list(fields, k)) then 
			table.insert(flist, k)
			remove_from_list(fields, k)
		elseif(is_in_list(containers, k)) then
			table.insert(clist, k)
			remove_from_list(containers, k)
		end
	end
	append_list(flist, fields)
	append_list(clist, containers)

	m._fields = flist
	m._containers = clist
	m._order = nil
end


prepare_master(master)
diff(one, two, master)


