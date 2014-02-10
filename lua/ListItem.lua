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

require("lua.Log")
require("lua.Validators")

LIST = {}			-- all the lists
DEF = {}			-- the field definitions
LCFG = {}			-- list configs (keys etc)
ListItem = {}		-- ListItem class
List = {}			-- List functions

--
-- We need to be able to create the base lists and set specific
-- configuration
--
function List.create(name, key)
	LIST[name] = {}
	LCFG[name] = {}
	LCFG[name].key = key
end

--
-- Find a ListItem in a list given a field and value to find
--
-- NOTE: we only search valid items
--
function List.findItem(listname, fieldname, value)
	for k,v in ipairs(LIST[listname]) do
		if(v.valid and v.config[fieldname] == value) then return v end
	end
	return nil
end

--
-- The base ListItem constructor is very simple, we just create an object
-- and set the metatable for object-like behaviours, this will generally
-- be overridden by sub-classes
--
-- We need a list name to add the item to, and a type to get field
-- definitions
--
function ListItem:inherit(listname, type)
	local item = {}

	-- Setup the object
	setmetatable(item, self)
	self.__index = self
	item.super = self

	return item
end

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
-- The apply function would validate any config-wide requirements and
-- then move the scratch to valid config ... any complex work should
-- be done by the child, we simply move the config here (i.e. it can't fail)
--
-- We do check for all required fields here and will set the "valid" field
-- accordingly.
--
-- @return the items valid status
--
function ListItem:apply()
	local valid = true;

	self.config = self.scratch
	self.scratch = nil

	-- Check for all required fields
	for k,v in pairs(self.fields) do
		if(v.required and not self.config[k]) then valid=false end
	end
	
	self.valid = valid
	return valid
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



