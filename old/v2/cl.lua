#!./luajit

package.path = "./lib/?.lua"
package.cpath = "./lib/?.so;./c/?.so"

require("readline");


local FAIL, PARTIAL, PASS = 0, 1, 2

--
-- One we get a keyword we store it so that subsequent checking
-- knows what we are doing.
--
-- If we successfully check the path, then we set the global
-- so that subsequent field checking code will work
--
local v_cmd
local v_path



function check_path(key, value)
	if(value) then return FAIL, FAIL end
	if(key == "fred") then return PASS, FAIL end
	return FAIL, FAIL
end

function check_field(key, value)
	return PASS, PASS
end

--
-- Sample command line editing code
--

local cmds = {
	["set"] = { [2] = check_path, ["*"] = check_field },
	["show"] = { [2] = check_path },
	["delete"] = { [2] = check_path },
	["exit"] = {},
	["help"] = {}
}

local checks = {}


function check_command(key, value)
	-- check for cached response first
	if(v_cmd == key) then return PASS end

	-- now prepare for proper check
	checks = nil
	v_cmd = nil
	v_path = nil

	if(value) then 
		return FAIL 
	end
	if(cmds[key]) then
		checks = cmds[key]
		v_cmd = key
		return PASS 
	end

	for k,_ in pairs(cmds) do
		if(k:sub(1,#key) == key) then 
			return PARTIAL 
		end
	end
	return FAIL
end

--
-- Split the line into an array with each element then being
-- syntax checked
--
function process_line(work, syntax)
	local items = {}
	local index, spos = 1, 1

	while(spos < #work) do
		local s,e,key, value
		local ks, ke, vs, ve, eq
		local kfail, vfail

		-- first remove any leading whitespace
		s,e = work:find("^%s+", spos)
		if(s) then spos = e+1 end

		-- find the key
		s,e,key = work:find("^([%w/_%-%+%.]+)%f[=%s%z]", spos)

		if(not s) then
			-- must be an error, so we will mark up to the space
			s,e = work:find("^[^%s]+", spos)
			ks, ke, kfail = s, e, 1
			goto done
		end

		-- either it's an empty field, or a quoted or plain value
		ks, ke = s, e
		spos = e + 1

		-- check for empty
		if(work:find("^%f[%s%z]", spos)) then goto done end
			
		-- check for quoted... (must not have garbage after)
		s,e,value = work:find("^=\"([^\"]*)\"%f[%s%z]", spos)
		if(s) then
			vs, ve = s, e
			goto done
		end

		-- if we don't have the close quote?
		s,e,value = work:find("^=\"([^\"]*)$", spos)
		if(s) then
			vs, ve, vfail = s, e, 1
			goto done
		end

		-- check for plain value (no quotes)
		s,e,value = work:find("^=([^%s\"\']*)%f[%s%z]", spos)
		if(s) then
			vs, ve = s, e
			goto done
		end

		-- otherwise we are an error, up to next space
		s,e = work:find("^[^%s]*", spos)
		vs, ve, vfail = s, e, 1
		goto done

::done::
		spos = e + 1

		local kcol, vcol = 1, 1		-- default to red
		local rck, rcv

		if(index == 1 and not kfail) then
			rck = check_command(key)
			if(rck == PASS) then kcol = 2 end
			if(rck == PARTIAL) then kcol = 5 end
		end

		if(index > 1 and not kfail) then
			local check_func = checks and (checks[index] or checks["*"])
			if(check_func) then
				rck, rcv = check_func(key, (vfail and nil) or value)
				if(rcv == PASS) then vcol=6 end
				if(rck == PASS) then kcol=6 end
				if(rck == PARTIAL) then kcol=4 end
			end
		end

		rl.set_syntax(syntax, ks, ke, kcol)

		if(eq) then
			rl.set_syntax(syntax, eq, eq, 4)
		end
		if(vs) then
			rl.set_syntax(syntax, vs, ve, vcol)
		end

		index = index + 1
	end
--	return items
end

function lee(a,b)
--	print("\n\nLEE CALLED WITH ["..tostring(a)..","..tostring(b).."]")

	-- how am I going to return the details for highlighting
	return 1
end


local line = ""

a="hello"

rl.readline(process_line)

--for x=1,50000 do
--	process_line("fred bill joe=45 x=999 seventy_five=adjkhdasfgjklhs dfsdf gsdfkgjh sdlfkgsdfg sdfgkljh sdflgjkh sdlfkgjh sdlkgh sldkfjhg skldjgh sdkljfh gsdkljfgh sdlkgsldkfgsdf=gsdfgsdfgsdfg sdfgsdfgsd=fgsdfgsdfg sdfgsd=fgsdfg");
--end

