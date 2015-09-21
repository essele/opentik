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
-- Run a command but allow passing input and collecting of output
--
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
-- Run a binary in the background and return its pid so we can kill it later
--
local function background(cmd, args)

	local rd, rw = posix.unistd.pipe()
	local cpid = posix.unistd.fork()
	if cpid ~= 0 then		-- parent
		posix.unistd.close(rw)
		local pid = posix.unistd.read(rd, 1024)
		print("Got pid of " .. pid)
		local rc, state, status = posix.sys.wait.wait(cpid)
		print("start as daemon rc="..tostring(rc).." state="..tostring(state).." status="..tostring(status))
		return tonumber(pid)
	end

	--
	-- We are the child, prepare for a second fork and exec.
	--
	posix.sys.stat.umask(0)
	if not posix.unistd.setpid("s") then os.exit(1) end
	if posix.unistd.chdir("/") ~= 0 then os.exit(1) end
	posix.unistd.close(0)
	posix.unistd.close(1)
	posix.unistd.close(2)

	--
	-- Fork again, so the parent can orphan the child
	--
	local npid = posix.unistd.fork()
	if npid ~= 0 then os.exit(0) end

	--
	-- Re-open filehandles as /dev/null
	--
	local fdnull = posix.fcntl.open("/dev/null", posix.fcntl.O_RDWR)	-- stdin
	posix.unistd.dup(fdnull)											-- stdout
	posix.unistd.dup(fdnull)											-- stderr

	posix.unistd.write(rw, tostring(posix.unistd.getpid()))
	posix.unistd.close(rw)

	posix.unistd.exec(cmd, args)
	os.exit(1)
end


return {
	execute = execute,
	background = background,
}

