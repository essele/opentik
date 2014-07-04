#!./luajit

--
-- Sample command line editing code
--

--
-- Split the line into an array with each element then being
-- syntax checked
--

function process_line(work)
	local items = {}
	local index, spos = 1, 1

	while(spos < #work) do
		local s,e,key,eq
--		print("Work is: [" .. work .. "]")

		-- try to find key="value value value"	
		s,e,key,eq,value = work:find("^%s*([^%s=]+)(=)\"([^\"]*)\"%s*", spos)
		if(not s) then s,e,key,eq,value = work:find("^%s*([^%s=]+)(=)([^%s]*)%s*", spos) end
		if(not s) then s,e,key = work:find("^%s*([^%s]+)%s*", spos) end
		if(not s) then print("UGH -- not match") end
	
--		print("Found: key=["..tostring(key).."] value=["..tostring(value).."] s="..s.." e="..e)
		spos = e+1
	
		items[index] = {
				["key"] = key,
				["equals"] = eq and 1,
				["value"] = value,
				["start"] = s, 
				["end"] = e }
	end
	return items
end



local line = ""

os.execute("stty raw -echo")

io.write(">> ")
while(1) do
	local x = io.read(1)
	if(x == "\127") then
		line = line:sub(1,#line-1)
--		io.write("\008")
		io.write("\008 \008")
	else
		line = line .. x
		io.write(x)
	end
	process_line(line)
--	io.write(string.byte(x))
	if(x == "x") then break end
end

os.execute("stty cooked echo")



--local line = "one two=x three=yyyfh four=\"a bcd efg\" dhdhdh defg=four5 lee= ghghg   "

