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

local function execute(cmd, args, stdin, env)
	-- Some debug
	print("["..cmd.." "..(table.concat(args or {}, " ")).."]")

	-- Now start
	local outr, outw = posix.unistd.pipe()
	local pid = posix.unistd.fork()
	if pid == 0 then
		-- child
		posix.unistd.close(outr)
		posix.unistd.dup2(outw, 1)
		posix.unistd.dup2(outw, 2)
	
		-- set environment if specified
		for k, v in pairs(env or {}) do posix.stdlib.setenv(k, v) end

		if stdin then
			local inr, inw = posix.unistd.pipe()
			if posix.unistd.fork() == 0 then
				-- real child
				posix.unistd.close(inw)
				posix.unistd.dup2(inr, 0)
				posix.unistd.exec(cmd, args or {})
				print("unable to exec")
				os.exit(1)
			end
			posix.unistd.close(inr)
			-- feed in the stdin data
			for _,line in ipairs(stdin) do
				posix.unistd.write(inw, line .. "\n")
			end
		else
			posix.unistd.exec(cmd, args or {})
			print("unable to exec")
			os.exit(1)
		end
	end
	posix.unistd.close(outw)
	local output = {}
	local outfh = posix.stdio.fdopen(outr, "r")
	for line in outfh:lines() do table.insert(output, line) end
	outfh:close()
	
	local pid, reason, status = posix.sys.wait.wait(pid)

	-- Some debug
	for _,o in ipairs(output) do print("> "..o) end

	return status, output
end


--
-- This module provides a simple interface into the iproute2 command set
--
local function addr_add(ip, dev)
	local st = execute("/sbin/ip", {"addr", "add", ip, "dev", dev }, nil, nil)
	return (st == 0)
end

local function addr_del(ip, dev)
	local st = execute("/sbin/ip", {"addr", "del", ip, "dev", dev }, nil, nil)
	return (st == 0)
end

local function link_set(dev, ...)
	local st = execute("/sbin/ip", {"link", "set", "dev", dev, ...})
	return (st == 0)
end


return {
	["addr"] = {
		["add"] = addr_add,
		["del"] = addr_del,
	},
	["route"] = {
	},
	["link"] = {
		["set"] = link_set,
	},
}



