#!./luajit

package.path = "./lib/?.lua"
package.cpath = "./lib/?.so;./c/?.so"

require("readline");


local OK = 1
local PARTIAL = 2
local FAIL = 3


--
-- Return the keys from a table as a list
--
function keys(t)
	local rc = {}
	for k,_ in pairs(t) do table.insert(rc, k) end
	return rc
end

--
-- Given a list and a partial string, return any items from the list that
-- match the string (partial match)
--
function get_matching(list, sofar)
	local rc = PARTIAL
	local rcl = {}

	for _,v in pairs(list) do
		if(sofar == v:sub(1,#sofar)) then
			table.insert(rcl, v)
			if(#sofar == #v) then rc = OK end
		end
	end
	if(rcl[1]) then
		return rc, rcl
	else
		return FAIL, nil
	end
end


function tokenize_line(work)
	local tokens = {}
	local index = 1
	local pos = 1
	while(pos < #work) do
		local s, e, key, eq, value
		local kerr, verr = nil, nil

		-- move past any leading space
		s, e = work:find("^%s+", pos)
		if(s) then pos = e + 1 end

		-- key or key=
		s, e, key, eq = work:find("^%f[^%s%z]([%a%-%./_]+)(=?)", pos)

		if(not s) then 
			-- ugh, all the rest is error
			s, e, kerr = pos, #work, FAIL
			key = work:sub(s, e)
		end

		token = { ["ks"] = s, ["ke"] = e, ["key"] = key, ["kerr"] = kerr }
		pos = e+1

		-- now pull out a value if we have one...
		if(eq == "=") then
			s, e, value = work:find("^([^%s\"]*)%f[%s%z]", pos)
			if(not s) then
				s, e, value = work:find("^\"([^\"]*)\"%f[%s%z]", pos)
			end
			if(not s) then
				s, e, verr = pos, #work, FAIL
				value = work:sub(s, e)
			end
			token["vs"] = s
			token["ve"] = e
			token["value"] = value
			token["verr"] = verr
			pos = e + 1 
		end

		tokens[index] = token
		index = index + 1
	end
	return tokens
end

--
-- See if the field is valid (for the given path) and then
-- run the validator to check the value
--
local CACHE_fields
function valid_field(key, value)
	if(CACHE_fields[key] and CACHE_fields[key] == value) then
		return OK, OK
	end

	if(key ~= "one" and key ~= "two") then
		return FAIL, FAIL
	end

	if(key == "one") then
		if(value ~= "fred") then return OK, FAIL end
	end
	if(key == "two") then
		if(value ~= "bill") then return OK, FAIL end
	end
	

	-- TODO: check if its a valid key
	-- TODO: run the validator to check value
	
	CACHE_fields[key] = value
	return OK, OK
end

--
-- See if the path is valid, and pull out the relevant part
-- of the config
--
local CACHE_path
local CACHE_master
function valid_path(path)
	if(path == CACHE_path) then return OK end

	if(path:sub(1,1) == "/") then
		CACHE_path = path
		CACHE_fields = {}
		return OK
	end
	return FAIL
end

function cmd_set(tokens)
	-- check we have a suitable token...
	local path = tokens[2] and not tokens[2].kerr and not tokens[2].value and tokens[2].key
	if(not path) then return 2 end

	-- check if valid
	local rc = valid_path(path)
	if(rc ~= OK) then
		tokens[2].kerr = rc
		return 3
	end

	-- now for all remaining, these should be key=value
	local index = 3
	while(tokens[index]) do
		local token = tokens[index]
		if(not token.kerr and not token.verr) then
			local krc, vrc = valid_field(token.key, token.value)
			token.kerr = ((krc ~= OK) and krc) or nil
			token.verr = ((vrc ~= OK) and vrc) or nil
		end
		index = index + 1
	end
end


local cmds = { 
	["set"] = cmd_set,
	["get"] = cmd_set,
	["show"] = cmd_show,
	["help"] = cmd_help
}


function syntax_check(tokens)
	local cmd, rc
	local index

	-- check our key is a full match for a command, if partial then mark
	cmd = tokens[1] and not tokens[1].kerr and not tokens[1].value and tokens[1].key
	if(not cmd) then goto failrest end

	-- check full match first, then partials...
	if(not cmds[cmd]) then
		rc = get_matching(keys(cmds), tokens[1].key)
		if(rc ~= OK) then
			tokens[1].kerr = rc
			index = 2
			goto failrest
		end
	end

	-- now run the command specific checker
	index = cmds[cmd](tokens)
	
::failrest::
	while(tokens[index]) do
		tokens[index].kerr = FAIL
		tokens[index].verr = FAIL
		index = index + 1
	end
end

function process_line(work, syntax)
	local toks = tokenize_line(work)
	syntax_check(toks)
	
	for _, t in ipairs(toks) do
		local col = 1
		-- key first
		if(t.kerr == PARTIAL) then col = 2 
		elseif(t.kerr == FAIL) then col = 3 end

		rl.set_syntax(syntax, t.ks, t.ke, col)

		-- value
		col = 1
		if(t.value) then
			if(t.verr == PARTIAL) then col = 2
			elseif(t.verr == FAIL) then col = 3 end
	
			rl.set_syntax(syntax, t.vs, t.ve, col)
		end
	end
end

CACHE_path = nil
CACHE_fields = {}


rl.readline(process_line)

for i,v in ipairs(toks) do
	print("----")
	for kk,vv in pairs(v) do
		print("k="..kk.." v="..vv)
	end
end
