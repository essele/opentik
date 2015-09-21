--------------------------------------------------------------------------------
--  This file is part of OpenTik
--  Copyright (C) 2014,15 Lee Essen <lee.essen@nowonline.co.uk>
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
------------------------------------------------------------------------------

--
-- Create the gloal CONFIG table
--
CONFIG = {}

--
--



--
-- Each item consists of:
--
-- 1. Config (what have you configured)
-- 		- defaults for non-entered config
--
-- 2. Live data
-- 		- includes config plus dynamic fields
-- 		- INVALID means not in the real system
-- 		- DISABLED means not in the real system
--
--
-- We require a mechanism to map live data back to config items,
-- for routes this is <dest>|<type>|<table>|<metric>
--
-- For ethernet we use default-name since the kernel will remain
-- on default
--


--
-- We differ from the mikrotik approach here, we will just look for the highest numbered
-- interface with the given prefix and go one bigger.
--
local function build_uniq_name(path, prefix) 
	local base = CONFIG[path]
	local regex = prefix:gsub("[%-%+]", "%%%1") .. "(%d+)"		 -- TODO: more regex?
	local i = 0
	local num

	for k,_ in pairs(CONFIG[path].cf) do
		local num = k:match(regex)
		if num and tonumber(num) > i then i = tonumber(num) end
	end
	i = i + 1
	return prefix .. i
end

--
-- The defaults metatable is used to gather default values for given fields by looking
-- within the fields, we keep the path and ci as local variables so we can use them if
-- we are doing function lookups
--
function set_defaults_metatable(path, ci)
	setmetatable(ci, { __index=function(t, k)
		--
		-- We only return defaults for defined fields
		--
		if not CONFIG[path].fields[k] then return nil end

		local default = CONFIG[path].fields[k].default
		if type(default) == "function" then
			return default(path, ci)
		else
			return default
		end
	end
	})
end

--
-- Call the _dependency_list function for a given item if the function
-- exists
--
local function dependency_list(path, ci)
	local uniq = ci._uniq
	local deps = CONFIG[path].dependencies
	local rc = {}

	if type(deps) == "table" then
		for field, dep in pairs(deps) do
			local duniq = ci[field]
			rc[field] = { path=dep.path, uniq=duniq, needrunning=dep.needrunning }

--		for field, dpath in pairs(deps) do
--			local duniq = ci[field]
--			rc[field] = { path=dpath, uniq=duniq }
		end
		return rc
	elseif type(deps) == "function" then
		return deps(path, ci)
	else
		return {}
	end
end

--
-- Dependency change tells a dependant that the parent has changed (or gone)
-- so it should update the relevant field(s) to reflect the change
--
-- TODO: may want to support a function here for special cases
--
local function dependency_change(path, uniq, field, dpath, dolduniq, dnewuniq)
	dnewuniq = dnewuniq or "unknown"

	print(string.format("DEPEND CHANGE FOR %s %s -> %s", dpath, dolduniq, dnewuniq))	
	print(string.format("IMPACTING %s %s %s", path, uniq, field))
	CONFIG[path].cf[uniq][field] = dnewuniq
end


--
-- Dump a table for debugging
--
local function cf_dump(t, indent)
	indent = indent or 0
	local space = string.rep(" ", indent)
	local rc = ""

	if type(t) == "table" then
		rc = rc .. "{\n"
		for k,v in pairs(t) do
			rc = rc .. space .. "   " .. k .. " = " .. cf_dump(v, indent+3) .. "\n"
		end
		rc = rc .. space .. "}"
	else
		rc = tostring(t)
	end
	return rc
end



--
-- Return a copy of the thing (mostly used for tables)
-- NOTE: currently does not copy keys that are tables
--
local function copy_of(i)
	if type(i) == "table" then
		local rc = {}
		for k,v in pairs(i) do rc[k] = copy_of(v) end
		return rc
	else
		return i
	end
end

--
-- Generate a random key that isn't already in the table, optionally
-- with a specific prefix
--
-- Seed once with time ... security isn't important, so this is ok
math.randomseed(os.time())

local function random_key(t, prefix)
	local k

	local function randomstring(x)
		local rs = {}
		for i=1, x do rs[i] = string.char(string.byte('a') + math.random(0,25)) end
		return table.concat(rs)
	end

	repeat k = (prefix or "") .. randomstring(8) until not t[k]
	return k
end

--
-- Add a dependent to the dependency list
--
local function add_dependent(ppath, puniq, cpath, cuniq, cfield)
	local pbase = CONFIG[ppath].dependents

	if not pbase[puniq] then pbase[puniq] = {} end
	table.insert(pbase[puniq], { path = cpath, uniq = cuniq, field = cfield })
end

--
-- Remove a dependent from the dependecy list
--
local function remove_dependent(ppath, puniq, cpath, cuniq, cfield)
	local pbase = CONFIG[ppath].dependents[puniq] or {}
	local i = 1
	while pbase[i] do
		if pbase[i].path == cpath and pbase[i].uniq == cuniq and pbase[i].field == cfield then
			table.remove(pbase, i)
		else
			i = i + 1
		end
	end
end

--
-- See if all the dependencies are dependable
--
local function all_dependable(path, ci)
	local rc = true

	for _,dep in pairs(dependency_list(path, ci)) do
		local base = CONFIG[dep.path]
		local live = base and base.live[dep.uniq]

		if not live or not live._dependable then rc = false end
	end
	return rc
end

--
-- Call the _build_uniq function for a given item
--
local function build_uniq(path, ci)
	local base = CONFIG[path]
	--
	-- See if we have a field with uniq set.
	--
	-- If set to true, then we use the field
	-- If it's a function, then we call the function
	--
	local uniq = nil
	for k,field in pairs(base.fields) do
		if field.uniq then
			-- If we have a value set, then use it regardless
			if ci[k] then return ci[k] end
			-- If uniq=<function> then call it
			if type(field.uniq) == "function" then return field.uniq(path, ci) end
		end
	end
	print("NO UNIQ FOUND for "..path)
	return random_key(base.live)
end

--
-- See if an item exists
--
local function exists(path, uniq)
	return CONFIG[path].live[uniq] and true
end

--
-- Remove keys where the value is the same as the default, we don't check
-- anything starting with a '_'.
--
local function prune_defaults(path, ci)
	for field,value in pairs(ci) do
		if field:sub(1,1) ~= "_" then 
			print("Prun check f="..field.." v="..tostring(value))
			if value == CONFIG[path].fields[field].default then ci[field] = nil end
		end
	end
end

--
-- States:
--
-- invalid = one or mode dependencies are not dependable
-- disabled = we are configured to be disabled (removes invalid)
-- running = an extra flag for relevant state
--
-- dependable = not disabled and then either (not invalid) or (running)
--
-- if it's not disabled and not invalid then the back-end should be up, this
-- will be set by this routine (backed) so we can compare history
--
local function state_change(path, uniq, going, goinvalid)
	local base = CONFIG[path]
	local live = base.live[uniq]
	local invalid = going or goinvalid or nil


	local backed = live._backed

	if not live.disabled then
		--
		-- Check our dependencies are valid
		--
		if not all_dependable(path, base.cf[uniq]) then invalid = true end
	end

	--
	-- If we weren't backed, but now need to be then we need to start the backend
	--
	if not backed and not live.disabled and not invalid then
		-- START
		print("Would start backend for "..path.." "..uniq)
		if base.options.start then
			base.options.start(path, base.cf[uniq])
		end
		live._backed = true
	end

	--
	-- What is our new dependable state?
	--
	local dependable = not live.disabled and not invalid
	-- TODO include optional running state

	-- Ensure our invalid flag is correct
	live._invalid = invalid

	--
	-- If we have changed state then tell our depedents
	--
	if dependable ~= live._dependable then
		live._dependable = dependable or nil

		for _,dep in ipairs(base.dependents[uniq] or {}) do
			if going then dependency_change(dep.path, dep.uniq, dep.field, path, uniq, nil) end
		print("DEPENTABLE CHANGE for "..path.."/"..uniq.." notifiying "..dep.path.."/"..dep.uniq)
			state_change(dep.path, dep.uniq)
		end
	end

	--
	-- If we were backed, but now we are not, then we need to stop
	--
	if backed and (live.disabled or invalid) then
		-- STOP
		print("Would stop backend for "..path.." "..uniq)
		if base.options.stop then
			base.options.stop(path, base.cf[uniq])
		end
		live._backed = false
	end
end



--
-- Set specific configuration fields. 
--
-- Since changes could chage the dependencies we remove them before the change
-- then add them back afterwards.
--
-- Before we do anything we should check the new dependencies to ensure they are
-- valid, otherwise we can reject the change.
--
--
--
local function cf_set(path, olduniq, items)
	local base = CONFIG[path]
	local oldci = olduniq and base.cf[olduniq]
	local newuniq = nil
	local ci = nil

	-- If we have some items then we need to build a representation of how
	-- the new cf will look, we copy the old one first if provided, then
	-- create the new uniq value and check all the dependencies are valid
	if items then
		ci = (oldci and copy_of(oldci)) or {}
		set_defaults_metatable(path, ci)

		for field,value in pairs(items) do ci[field] = value end
		prune_defaults(path, ci)

		-- We should check all of the dependencies to make sure they exist
		-- at this point (dependable checks will be later)
		newuniq = build_uniq(path, ci)
		ci._uniq = newuniq
		for _,dep in pairs(dependency_list(path, ci)) do
			if not exists(dep.path, dep.uniq) then
				print("Dependency not present: "..dep.path.." "..dep.uniq)
				return false
			end
		end
	end

	--
	-- Regardless of what we are doing we need to remove any existing registered
	-- dependencies since they might change (we will add them back later if needed)
	--
	if oldci then
		--
		-- Remove our dependency registrations
		--
		for field,dep in pairs(dependency_list(path, oldci)) do 
			remove_dependent(dep.path, dep.uniq, path, olduniq, field) 
		end

		--
		-- We need to shut down to make whatever changes are needed, if we are
		-- being removed then we handle it differently
		--
		-- TODO: make the shut down optional if only minor fields are changing
		--
		if ci then
			state_change(path, olduniq, false, true)
		else
			state_change(path, olduniq, true)

			--
			-- Allow post-processing to handle the remove
			--
			if base.options["ci-post-process"] then
				base.options["ci-post-process"](path, oldci, true)
			end

			base.cf[olduniq] = nil
			base.live[olduniq] = nil
			base.dependents[olduniq] = nil
		end

		--
		-- Remove the old config ... it will be replaced below if needed
		-- TODO: duplicate of above, remove from there?
		base.cf[olduniq] = nil

		--
		-- Update our mirror if needed
		--
		if base.options.duplicate then
			CONFIG[base.options.duplicate].cf[olduniq] = base.cf[olduniq]
			CONFIG[base.options.duplicate].live[olduniq] = base.live[olduniq]
		end
	end


	--
	-- Now we can put in the new
	--
	if ci then
		local dependencies = dependency_list(path, ci)

		--
		-- Ensure we move stuff across, caters for change of uniq, including updating any
		-- dependents
		--
		base.cf[newuniq] = ci
		base.live[newuniq] = base.live[olduniq] or {}
		base.dependents[newuniq] = base.dependents[olduniq] or {}
		setmetatable(base.live[newuniq], { __index = ci })

		if olduniq and olduniq ~= newuniq then
			base.live[olduniq] = nil
			base.dependents[olduniq] = nil

			for _,dep in ipairs(base.dependents[newuniq] or {}) do
				dependency_change(dep.path, dep.uniq, dep.field, path, olduniq, newuniq)
			end
		end

		--
		-- Call the function to handle the field changes, if the item is not backed this doesn't do
		-- anything (since it will all happen at start). If the item is backed then these are minor
		-- changes that can be done on the fly.
		--
		-- TODO: include check for _backed
		if oldci then
			local changed = {}
			for k,v in pairs(oldci or {}) do changed[k] = (oldci[k] ~= ci[k]) or nil end
			for k,v in pairs(ci or {}) do changed[k] = (ci[k] ~= oldci[k]) or nil end
			print("CHANGED: ")
			print(lib.cf.dump(changed))
		end

		--
		-- Allow post-change postprocessing
		--
		if base.options["ci-post-process"] then
			base.options["ci-post-process"](path, ci)
		end

		--
		-- Install our dependencies
		--
		for field,dep in pairs(dependencies) do 
			add_dependent(dep.path, dep.uniq, path, newuniq, field) 
		end

		--
		-- Honor the options.duplicte setting before calling state_change
		--
		if base.options.duplicate then
			CONFIG[base.options.duplicate].cf[newuniq] = base.cf[newuniq]
			CONFIG[base.options.duplicate].live[newuniq] = base.live[newuniq]
		end

		--
		-- Call state change to action any changes
		--
		state_change(path, newuniq)
	end	
	return newuniq
end


--
-- Allow the registration of config sections. This basically adds the structure
-- to the global config and then ensures that the relevant tables are setup to 
-- save a load of checking in the code.
--
local function cf_register(path, config)
	CONFIG[path] = config;

	config.cf = {}
	config.live = {}
	config.dependents = {}
	config.options = config.options or {}

	-- TODO: some sanity checks to ensure things won't break later
	--
	-- 1. Any field in "field-order" actually exists
	--

	--
	-- Use a sorted field order if we don't have one
	--
	if not config.options["field-order"] then
		config.options["field-order"] = {}
		for f,_ in pairs(config["fields"]) do
			table.insert(config.options["field-order"], f)
		end
		table.sort(config.options["field-order"])
	end
end

--
-- Iterate through the config's fields in the order provided and
-- return each field (that exists) in turn.
--
local function each_field(base)
	local order = base.options["field-order"]
	local i = 0

	return function()
		i = i + 1
		if not order[i] then return end
		return order[i], base.fields[order[i]]
	end
end
	

--
-- Basic printing function
--
local function cf_print(path)
	local base = CONFIG[path]


	local function build_flags(live)
		local rc = {}

		for i, f in pairs(base.flags) do
			rc[f.pos] = (live[f.field] and f.flag) or rc[f.pos] or " "
		end
		return table.concat(rc)
	end

	--
	-- Flags header
	--
	io.write("Flags: ")
	for i, f in pairs(base.flags) do
		if i > 1 then io.write(", ") end
		io.write(string.format("%s - %s", f.flag, f.name))
	end
	io.write("\n")


	for uniq, live in pairs(base.live) do
		print("Got: "..uniq)

		print("Flags: [" .. build_flags(live) .. "]")

		for fname, field in each_field(base) do
			local v = live[fname]
			local prep = field.prep

			if prep == false then v = nil
			elseif type(prep) == "function" then v = prep(fname, live)
			end
				
			if v then
				print(string.format("  %s=%s", fname, live[fname]))
			end
		end
	end
end

return {
	set = cf_set,
	register = cf_register,
	dump = cf_dump,
	print = cf_print,
}








