--
-- Lists are the basic config and live data mechanism within OpenTik
--
-- Each list supports a set of fields for each record and then has
-- a set of validators to ensure the value is acceptable.
--
-- There are several important fields within a list object:
--
-- fields 	 - set by the constructor, defines which fields are available
-- config    - the configuration of this item
-- scratch 	 - the working set config for changes/reversions
--
-- States
--	valid    -- valid config, i.e. enough to be ok at some point
--	enabled  -- allows toggling (basically removing)
--	active   -- when it is live
--
--

require("Log")
require("Validators")

LIST = {}			-- all the lists
DEF = {}			-- the field definitions
LCFG = {}			-- list configs (keys etc)
DEPS = {}			-- dependencies (key=topic, value=list of items)
DEPV = {}			-- cache of dependency values

--
-- The ListItem and List classes
--
ListItem = {}		-- ListItem class
List = {}			-- List functions

--
-- We need to be able to create the base lists and set specific
-- configuration. Here we subscribe to the command channel for the
-- given list
--
function List.create(name, key, object)
	LIST[name] = {}
	LCFG[name] = {}
	LCFG[name].key = key
	LCFG[name].object = object
end

--
-- Helper function to remove an item from a list
--
function remove_from_list(list, item)
	local pos = nil

	for i,v in ipairs(list) do
		if(v == item) then pos = i break end
	end

	if(pos) then table.remove(list, pos) return 1 end
	return 0
end

--
-- We need to be able to load and save the config from the
-- config files
--
function List.save(listname)
	local data
	local fh = io.open("conf/"..listname..".conf", "w")
	
	if(not fh) then error("unable to write config") end

	for i,v in ipairs(LIST[listname]) do
		-- TODO: handle enabled/disabled
		data = unit.serialize(v.config)
		fh:write(data, "\n")
	end
	fh:close()
end
function List.load(listname)
	local item
	local config

	local fh = io.open("conf/"..listname..".conf", "r")
	
	if(not fh) then error("unable to read config") end
	
	for data in fh:lines() do
		config = unit.unserialize(data)
		print("Data is: "..data);
		print("config is: "..tostring(config))
		print("type is: "..tostring(config.type))
		item = LCFG[listname].object.from_config(config)
		item:apply()
	end	
end


--
-- Dependency callback ... when any of our dependencies change
-- we will get called. Our job is to go through the list items
-- calling set_state()
--
function List.cb_dependencies(topic, value)
	local items = DEPS[topic]

	print("Got topic callback for: " .. topic)
	DEPV[topic] = value

	-- Call set_state() on each of our lists
	for i,item in ipairs(items) do
		item:set_state()
	end
end
function List.add_dependency(topic, item)
	local items = DEPS[topic]

	if(not items) then
		mosquitto.subscribe(topic, List.cb_dependencies)
		DEPS[topic] = {}
		DEPV[topic] = nil			-- remove prior cache if there is one
		print("Added subscription for topic: " .. topic)
		items = DEPS[topic]
	else
		-- ensure we don't duplicate
		remove_from_list(items, item)
	end
	table.insert(items, item)
end

function List.remove_dependency(topic, item)
	local items = DEPS[topic]

	if(not items) then return end
	if(remove_from_list(items, item) == 1) then
		if(#items == 0) then
			mosquitto.unsubscribe(topic)
			DEPS[topic] = nil
			DEPV[topic] = nil
			print("Removed subscription for topic: " .. topic)
		end
	end
end

--
-- Find a ListItem in a list given a field and value to find (and also a 2 field version)
--
-- NOTE: we only search valid items and non-disabled
--
function List.findItem(listname, fieldname, value)
	for k,v in ipairs(LIST[listname]) do
		if(v.valid and v.enabled and v.config[fieldname] == value) then return v end
	end
	return nil
end
function List.findItem2(listname, fieldname1, value1, fieldname2, value2)
	for k,v in ipairs(LIST[listname]) do
		if(v.valid and v.enabled and 
			v.config[fieldname1] == value1 and v.config[fieldname2] == value2) then return v end
	end
	return nil
end

--
-- The base ListItem constructor is very simple, we just create an object
-- and set the metatable for object-like behaviours, this will generally
-- be overridden by sub-classes
--
function ListItem:inherit()
	local item = {}

	-- Setup the object
	setmetatable(item, self)
	self.__index = self
	item.super = self

	return item
end

--
-- The init function sets up sensible defaults, stores the field
-- definitions.
--
function ListItem:init(listname, type)
	-- Get the field definitions
	if(not DEF[type]) then
		Log.debug("unknown field definition type: "..type)
		return nil
	end
	self.fields = DEF[type].fields
	
	-- Set our list reference
	self.list = LIST[listname]

	-- Create required bits
	self.config = {}				-- live config
	self.scratch = nil				-- scratch area for config changes
	self.valid = false				-- we start invalid (until we learn otherwise)
	self.enabled = true				-- we start enabled
	self.active = false				-- we start inactive

	-- Prepare for our dependencies
	self.depends = {}
	
	-- Populate the default entries
	self:defaults()

	-- Add ourself to the list
	table.insert(LIST[listname], self)

	return true
end

--
-- Once we create an item we should populate the default fields into the
-- config (only if the fields are required)
--
-- TODO: config or scratch?
--
function ListItem:defaults()
	local fname,f

	Log.debug("running defaults()")

	for fname,f in pairs(self.fields) do
		if(f.required) then
			if(type(f.default) == "function") then
				self.config[fname] = f.default(self.list, f, fname)
				Log.debug("default, set "..fname.."="..self.config[fname])
			elseif(f.default) then
				self.config[fname] = f.default
				Log.debug("default, set "..fname.."="..self.config[fname])
			end
		end
	end
end

--
-- When we set an item we are only affecting the "scratch" area, we need
-- to do basic validation of the field so we only allow syntactically valid
-- settings to make it to "scratch" and then on to config
--
-- If we don't have a scratch area then we copy the config
--
function ListItem:set(item, value)
	local f,validator,valid

	-- Make sure we have a scratch area properly setup
	if(not self.scratch) then
		self.scratch = {}
		for k,v in pairs(self.config) do self.scratch[k] = v end
	end

	-- Check for valid (and non internal) field
	f = self.fields[item]
	if(not f or f.type == "internal") then
		Log.debug("attempt to set invalid field: "..item)
		return false
	end

	-- Run the defined or standard valiator
	validator = f.validator or Validators[f.type]
	if(validator) then
		valid = validator(f, item, value)
	else
		Log.debug("missing validator for type: "..f.type)
		valid = false
	end

	-- Now check if we are unique (if we are required to be)
	if(f.unique) then
		for i,entry in ipairs(self.list) do
			if(entry ~= self and entry.config[item] == value) then
				valid = false 
				break
			end
		end
	end

	Log.debug("ListItem:set("..item..", "..value..") valid=["..tostring(valid).."]")
	
	if(valid) then self.scratch[item] = value end
	return valid
end

--
-- When we get a value we should return the default if the value
-- isn't included in the config.
-- NOTE: this is from config, not scratch.
--
function ListItem:get(item)
	if(self.config[item] ~= nil) then return self.config[item] end
	if(self.fields[item].default ~= nil) then 
		if(type(self.fields[item].default) == "function") then
				self.config[fname] = f.default(self.list, f, fname)
			return self.fields[item].default(self.list, self.fields[item], item)
		else
			return self.fields[item].default
		end
	end
	return nil
end

--
-- The set_state function is called when we think we might need to
-- make changes to the state of the item. Generally this is when we
-- have changed valid/invalid or enabled/disabled or if we have
-- a depedency change.
--
-- If we are valid and enabled then we need to check he dependencies.
--   If we pass, then we will go live (either add or change)
--   If we fail, then we remove (if we were live before)
--
-- If we are not valid or not enabled then we remove (if live before)
--
function ListItem:set_state(old_config)
	local was_active = self.active
	local remove = true;			-- remove unless all ok
	local dep_pass = true

	if(self.valid and self.enabled) then
		-- Check dependencies
		for d,v in pairs(self.depends) do
			if(DEPV[d] ~= v) then dep_pass=false end
		end
		if(dep_pass) then
			if(not was_active) then
				-- TODO: rc
				self:action_create()
			elseif(old_config) then
				-- TODO: rc
				self:action_change(old_config)
			end
			self.active = true;
			remove = false;
		end
	end

	if(remove) then
		-- not ready, so remove if we were active before
		if(was_active) then
			-- TODO: check return codes
			self:action_remove()
		end
		self.active = false;
	end
end

--
-- The apply function takes any scratch config and applies it to the live
-- config. It then works out if the result it valid or not.
--
-- If we are not valid, but we were, then we remove our dependencies.
--
-- If we are now valid, then we build dependencies based on the new config.
--
-- We then call set_state("config") to cause a state and dependency
-- check based on the situation.
--
function ListItem:apply()
	local valid = true;
	local was_valid = self.valid
	local was_enabled = self.enable
	local old_config = {}

	-- Check for enablement
	if(self.scratch.enable) then
		self.enable = self.scratch.enable
		self.scratch.enable = nil
	end

	-- Keep a copy of our old config (for changes)
	for k,v in pairs(self.config) do old_config[k] = v end

	-- Update the config
	self.config = self.scratch
	self.scratch = nil

	-- Check for all required fields
	for k,v in pairs(self.fields) do
		if(v.required and not self.config[k]) then valid=false end
	end
	self.valid = valid

	--
	-- If we are potentially valid at this point we need to build
	-- our dependencies, otherwise we can remove our dependencies 
	-- because we're not going to happen anyway
	--
	if(self.valid and self.enabled) then
		-- Object level depedency creation...
		if(self.build_depends) then
			self:build_depends(old_config)
		end
	else
		self:clear_depends()
	end

	--
	-- Now call set_state() to cause the right thing to happen
	--
	self:set_state(old_config)

	-- TODO: this doesn't make sense to return
	return valid
end
function ListItem:enable()
	if(not self.enabled and self.valid) then
		self.enabled = true
		if(self.build_depends) then self:build_depends() end
		self:set_state()
	end
end
function ListItem:disable()
	if(self.enabled and self.valid) then
		self:clear_depends()
		self:set_state()
	end
	self.enabled = false
end

--
-- We support adding and removing dependencies
--
function ListItem:add_dependency(topic, value)
	self.depends[topic] = value
	List.add_dependency(topic, self)
end
function ListItem:remove_dependency(topic)
	self.depends[topic] = nil;
	List.remove_dependency(topic, self)
end
function ListItem:clear_depends()
	for topic,v in pairs(self.depends) do
		List.remove_dependency(topic, self)
	end
	self.depends = {}
end

--
-- The revert function will throw away the scratch section
-- it will be created from config if we try to set something
--
function ListItem:revert()
	self.scratch = {}
end

--
-- HELPER FUNCTION:
--
-- If we have a required field then we can specify an automatically
-- generated name
--
function ListItem.namegen(list, f, fname)
	local prefix = f.ngprefix or "item"
	local regex = "^" .. prefix .. "(%d+)$"
	local k,v,m
	local i = 0

	for i,v in ipairs(list) do
		m = string.match(v.config[fname], regex)
		if(m and tonumber(m) > i) then i=m end
	end
	return prefix .. (i+1)
end

