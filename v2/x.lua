#!./luajit


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
		local kerr = nil
		local verr = nil

		-- key or key=
		s, e, key, eq = work:find("^%s*%f[^%s%z]([%a%-%./_]+)(=?)", pos)

		if(not s) then 
			-- ugh, all the rest is error
			s, e, kerr = pos, #work, FAIL
			key = work:sub(s, e)
		end

		token = { ["ks"] = s, ["ke"] = e, ["key"] = key, ["kerr"] = kerr }
		pos = e+1

		-- now pull out a value if we have one...
		if(eq == "=") then
			s, e, value = work:find("^([^%s\"]+)%f[%s%z]", pos)
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

function valid_path(path)
	return OK
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
end


local cmds = { 
	["set"] = cmd_set,
	["get"] = cmd_set,
	["show"] = cmd_show,
	["help"] = cmd_help
}


function syntax_check(tokens)
	local index = 1
	local cmd, rc

	-- check our key is a full match for a command, if partial then mark
	cmd = tokens[1] and not tokens[1].kerr and not tokens[1].value and tokens[1].key
	if(not cmd) then goto failrest end

	rc = get_matching(keys(cmds), tokens[1].key)
	if(rc ~= OK) then
		tokens[1].kerr = rc
		index = 2
		goto failrest
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


local toks = tokenize_line("set blah fred=10 blsah=hello ghghgh=\"abf def\"")
syntax_check(toks)

--[[
for i,v in ipairs(toks) do
	print("----")
	for kk,vv in pairs(v) do
		print("k="..kk.." v="..vv)
	end
end
]]--
